import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Darwin.Mach
import ScreenCaptureKit

enum ScreenCaptureServiceError: LocalizedError {
    case permissionDenied
    case mainDisplayUnavailable
    case noRegionsConfigured
    case invalidRegions([CaptureRegionKind])
    case unableToAddStreamOutput(Error)
    case refreshTimedOut
    case captureStopped

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required."
        case .mainDisplayUnavailable:
            return "The main display is not available to ScreenCaptureKit."
        case .noRegionsConfigured:
            return "At least one capture region must be configured."
        case .invalidRegions(let kinds):
            let names = kinds.map(\.rawValue).joined(separator: ", ")
            return "Capture regions must fit completely inside the main display: \(names)."
        case .unableToAddStreamOutput(let error):
            return "Unable to attach the ScreenCaptureKit output: \(error.localizedDescription)"
        case .refreshTimedOut:
            return "Timed out waiting for a complete screen frame."
        case .captureStopped:
            return "Screen capture stopped before a complete frame was available."
        }
    }
}

/// ScreenCaptureKit displayTime is mach absolute ticks (SCStream.h).
/// Map elapsed ticks onto the same systemUptime clock used by action deadlines.
enum CaptureFrameTiming {
    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    static func captureUptime(
        displayTime: UInt64,
        currentTicks: UInt64 = mach_absolute_time(),
        currentUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        secondsPerTick: Double? = nil
    ) -> TimeInterval? {
        guard displayTime > 0 else { return nil }
        let tickDuration = secondsPerTick ?? Self.secondsPerTick
        // WindowServer can deliver a complete frame before its scheduled display time.
        // Keep freshness conservative by clamping a small lead to callback time.
        if displayTime > currentTicks {
            let lead = Double(displayTime - currentTicks) * tickDuration
            return lead <= 0.050 && currentUptime.isFinite && currentUptime >= 0 ? currentUptime : nil
        }
        let age = Double(currentTicks - displayTime) * tickDuration
        let uptime = currentUptime - age
        return uptime.isFinite && uptime >= 0 ? uptime : nil
    }
}

/// Serially processes one value at a time while retaining only the newest pending value.
final class LatestFrameProcessor<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private let handler: (Element) -> Void
    private let onDroppedFrame: () -> Void
    private var isProcessing = false
    private var pending: Element?
    private var isStopped = false

    init(
        queue: DispatchQueue,
        onDroppedFrame: @escaping () -> Void = {},
        handler: @escaping (Element) -> Void
    ) {
        self.queue = queue
        self.handler = handler
        self.onDroppedFrame = onDroppedFrame
    }

    func submit(_ element: Element) {
        var dropped = false
        let shouldStart: Bool = lock.withLock {
            guard !isStopped else { return false }
            if isProcessing {
                dropped = pending != nil
                pending = element
                return false
            }
            isProcessing = true
            return true
        }

        if dropped { onDroppedFrame() }
        guard shouldStart else { return }
        queue.async { [weak self] in
            self?.process(element)
        }
    }

    func cancelPending() {
        lock.withLock {
            pending = nil
        }
    }

    func stop() {
        lock.withLock {
            isStopped = true
            pending = nil
        }
    }

    private func process(_ element: Element) {
        handler(element)

        let shouldContinue: Bool = lock.withLock {
            guard !isStopped else {
                isProcessing = false
                pending = nil
                return false
            }

            if pending != nil {
                return true
            }

            isProcessing = false
            return false
        }

        guard shouldContinue else { return }
        queue.async { [weak self] in
            self?.processPending()
        }
    }

    private func processPending() {
        let element: Element? = lock.withLock {
            guard !isStopped, let pending else {
                isProcessing = false
                self.pending = nil
                return nil
            }
            self.pending = nil
            return pending
        }

        guard let element else { return }
        process(element)
    }
}

final class ScreenCaptureService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    typealias FrameHandler = (CapturedFrame) -> Void
    typealias StateHandler = (BotRunState) -> Void

    static let shared = ScreenCaptureService()

    private final class FrameWaiter {
        let id: UUID
        let generation: UInt64
        let continuation: CheckedContinuation<CapturedFrame, Error>
        var timeoutWorkItem: DispatchWorkItem?

        init(
            id: UUID,
            generation: UInt64,
            continuation: CheckedContinuation<CapturedFrame, Error>
        ) {
            self.id = id
            self.generation = generation
            self.continuation = continuation
        }
    }

    private let stateLock = NSLock()
    private let outputQueue = DispatchQueue(
        label: "com.pixelbot.tibia.screen-capture-output",
        qos: .userInteractive
    )
    private let processingQueue = DispatchQueue(
        label: "com.pixelbot.tibia.ocr-processing",
        qos: .userInitiated
    )
    private let processingQueueKey = DispatchSpecificKey<Void>()

    private var stream: SCStream?
    private var display: SCDisplay?
    private var streamConfiguration: SCStreamConfiguration?
    private var lifecycleRevision: UInt64 = 0
    private var latestProcessor: LatestFrameProcessor<CapturedFrame>?

    private var _runState: BotRunState = .stopped
    private var _currentGeneration: UInt64 = 0
    private var _currentFrame: CapturedFrame?
    private var lastDisplayTime: UInt64 = 0
    private var lastFrameDiagnosticUptime: TimeInterval = 0
    private var _regions = CaptureRegions()
    private var _sourceRect = CGRect.zero
    private var frameHandler: FrameHandler?
    private var stateHandler: StateHandler?
    private var acceptsFrames = false
    private var isStopping = false
    private var activeStreamIdentifier: ObjectIdentifier?
    private var waiters: [UUID: FrameWaiter] = [:]
    private var _lastError: Error?

    var runState: BotRunState {
        stateLock.withLock { _runState }
    }

    var currentGeneration: UInt64 {
        stateLock.withLock { _currentGeneration }
    }

    var currentFrame: CapturedFrame? {
        stateLock.withLock { _currentFrame }
    }

    var configuredRegions: CaptureRegions {
        stateLock.withLock { _regions }
    }

    var lastError: Error? {
        stateLock.withLock { _lastError }
    }

    override init() {
        super.init()
        processingQueue.setSpecific(key: processingQueueKey, value: ())
    }

    /// Checks TCC and optionally asks macOS to present the Screen Recording prompt.
    func checkPermission(requestIfNeeded: Bool = true) -> Bool {
        let granted = CGPreflightScreenCaptureAccess()
        if !granted && requestIfNeeded {
            CGRequestScreenCaptureAccess()
        }
        return granted
    }

    /// Runs manual OCR on the same serial queue as continuous frame processing.
    func performOnProcessingQueue<Result>(
        _ operation: @escaping () -> Result
    ) async -> Result {
        if DispatchQueue.getSpecific(key: processingQueueKey) != nil {
            return operation()
        }

        return await withCheckedContinuation { continuation in
            processingQueue.async {
                continuation.resume(returning: operation())
            }
        }
    }

    /// Starts a continuous, main-display-only stream. Call lifecycle methods from MainActor.
    @MainActor
    @discardableResult
    func start(
        regions: CaptureRegions,
        frameHandler: @escaping FrameHandler,
        stateHandler: StateHandler? = nil
    ) async throws -> UInt64 {
        if stream != nil {
            stateLock.withLock {
                self.frameHandler = frameHandler
                self.stateHandler = stateHandler
            }
            return try await updateRegions(regions)
        }

        lifecycleRevision &+= 1
        let revision = lifecycleRevision
        var attemptedStream: SCStream?

        stateLock.withLock {
            self.frameHandler = frameHandler
            self.stateHandler = stateHandler
        }

        guard checkPermission(requestIfNeeded: true) else {
            transition(to: .needsPermission)
            throw ScreenCaptureServiceError.permissionDenied
        }

        transition(to: .starting)

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard revision == lifecycleRevision else {
                throw ScreenCaptureServiceError.captureStopped
            }
            let mainDisplayID = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) else {
                throw ScreenCaptureServiceError.mainDisplayUnavailable
            }

            let configuration = try makeConfiguration(for: regions, display: display)
            let ownWindows = content.windows.filter {
                $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
            }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            attemptedStream = stream

            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            } catch {
                throw ScreenCaptureServiceError.unableToAddStreamOutput(error)
            }

            let generation = prepareForCapture(
                regions: regions,
                sourceRect: configuration.sourceRect,
                frameHandler: frameHandler,
                stateHandler: stateHandler,
                stream: stream
            )
            self.stream = stream
            self.display = display
            streamConfiguration = configuration

            try await stream.startCapture()
            guard revision == lifecycleRevision, self.stream === stream else {
                throw ScreenCaptureServiceError.captureStopped
            }
            return generation
        } catch {
            guard revision == lifecycleRevision else {
                throw ScreenCaptureServiceError.captureStopped
            }

            let failedStream = attemptedStream
            if let failedStream, stream === failedStream {
                stream = nil
                display = nil
                streamConfiguration = nil
            }
            let processor: LatestFrameProcessor<CapturedFrame>? = stateLock.withLock {
                _lastError = error
                acceptsFrames = false
                let processor = latestProcessor
                latestProcessor = nil
                activeStreamIdentifier = nil
                isStopping = false
                return processor
            }
            processor?.stop()
            transition(to: .captureFailed, error: error)
            if let failedStream {
                try? await failedStream.stopCapture()
                try? failedStream.removeStreamOutput(self, type: .screen)
            }
            throw error
        }
    }

    /// Reconfigures the active stream after invalidating all queued frames.
    @MainActor
    @discardableResult
    func updateRegions(_ regions: CaptureRegions) async throws -> UInt64 {
        guard let stream, let display else {
            throw ScreenCaptureServiceError.captureStopped
        }

        let configuration = try makeConfiguration(for: regions, display: display)
        lifecycleRevision &+= 1
        let revision = lifecycleRevision
        let generation: UInt64 = stateLock.withLock {
            _currentGeneration &+= 1
            _currentFrame = nil
            lastDisplayTime = 0
            _regions = regions
            _sourceRect = configuration.sourceRect
            acceptsFrames = false
            return _currentGeneration
        }
        let processor = stateLock.withLock { latestProcessor }
        processor?.cancelPending()
        transition(to: .starting)

        do {
            try await stream.updateConfiguration(configuration)
            guard revision == lifecycleRevision, self.stream === stream else {
                throw ScreenCaptureServiceError.captureStopped
            }
            streamConfiguration = configuration
            stateLock.withLock {
                acceptsFrames = true
            }
            return generation
        } catch {
            guard revision == lifecycleRevision, self.stream === stream else {
                throw ScreenCaptureServiceError.captureStopped
            }
            stateLock.withLock {
                _lastError = error
            }
            transition(to: .captureFailed, error: error)
            throw error
        }
    }

    /// Returns the latest active frame, or starts a short one-frame stream while stopped.
    @MainActor
    func refreshFrame(
        regions: CaptureRegions,
        timeout: TimeInterval = 2.0
    ) async throws -> CapturedFrame {
        if let frame = currentFrame,
           frame.generation == currentGeneration,
           runState == .running {
            return frame
        }

        let startedTemporarily = stream == nil
        let generation: UInt64
        if startedTemporarily {
            generation = try await start(
                regions: regions,
                frameHandler: { _ in },
                stateHandler: nil
            )
        } else {
            generation = currentGeneration
        }

        do {
            let frame = try await waitForFrame(generation: generation, timeout: timeout)
            if startedTemporarily, currentGeneration == generation {
                await stop()
            }
            return frame
        } catch {
            if startedTemporarily, currentGeneration == generation {
                await stop()
            }
            throw error
        }
    }

    @MainActor
    func stop() async {
        lifecycleRevision &+= 1
        let revision = lifecycleRevision
        let activeStream = stream
        stream = nil
        display = nil
        streamConfiguration = nil
        let processor: LatestFrameProcessor<CapturedFrame>? = stateLock.withLock {
            isStopping = true
            acceptsFrames = false
            _currentFrame = nil
            _currentGeneration &+= 1
            frameHandler = nil
            activeStreamIdentifier = nil
            let processor = latestProcessor
            latestProcessor = nil
            return processor
        }
        processor?.stop()
        failAllWaiters(with: ScreenCaptureServiceError.captureStopped)
        transition(to: .stopped)
        stateLock.withLock {
            stateHandler = nil
        }

        if let activeStream {
            do {
                try await activeStream.stopCapture()
            } catch {
                if revision == lifecycleRevision {
                    stateLock.withLock {
                        _lastError = error
                    }
                }
            }
            try? activeStream.removeStreamOutput(self, type: .screen)
        }

        if revision == lifecycleRevision {
            stateLock.withLock {
                isStopping = false
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        if outputType == .screen {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastFrameDiagnosticUptime >= 5 {
                lastFrameDiagnosticUptime = now
                PixelBotDiagnosticLogger.shared.log("capture_frame", fields: [
                    "status": .integer(frameStatus(in: sampleBuffer)?.rawValue ?? -1),
                    "lastAcceptedDisplayTime": .string(String(stateLock.withLock { lastDisplayTime })),
                ])
            }
        }
        guard outputType == .screen,
              frameStatus(in: sampleBuffer) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }

        let snapshot: (
            generation: UInt64,
            sourceRect: CGRect,
            processor: LatestFrameProcessor<CapturedFrame>
        )? = stateLock.withLock {
            guard acceptsFrames,
                  activeStreamIdentifier == ObjectIdentifier(stream),
                  let latestProcessor else {
                return nil
            }
            return (_currentGeneration, _sourceRect, latestProcessor)
        }

        guard let snapshot else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let displayTime = attachments.first?[.displayTime] as? UInt64,
              let captureUptime = CaptureFrameTiming.captureUptime(displayTime: displayTime) else {
            DiagnosticMetrics.shared.record(.invalidFrameTiming)
            return
        }
        let frame = CapturedFrame(
            pixelBuffer: pixelBuffer,
            sourceRect: snapshot.sourceRect,
            generation: snapshot.generation,
            timestamp: Date().addingTimeInterval(captureUptime - ProcessInfo.processInfo.systemUptime),
            captureUptime: captureUptime
        )

        let accepted: Bool = stateLock.withLock {
            guard acceptsFrames, _currentGeneration == frame.generation, displayTime > lastDisplayTime else { return false }
            lastDisplayTime = displayTime
            _currentFrame = frame
            return true
        }
        guard accepted else { return }
        resumeWaiters(with: frame)

        transitionToRunningIfStarting()
        snapshot.processor.submit(frame)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let processor: LatestFrameProcessor<CapturedFrame>? = stateLock.withLock {
            guard activeStreamIdentifier == ObjectIdentifier(stream), !isStopping else {
                return nil
            }
            acceptsFrames = false
            _currentFrame = nil
            _currentGeneration &+= 1
            _lastError = error
            activeStreamIdentifier = nil
            return latestProcessor
        }
        guard let processor else { return }

        processor.stop()
        failAllWaiters(with: error)
        Task { @MainActor [weak self] in
            self?.handleUnexpectedStop(of: stream, error: error)
        }
    }

    @MainActor
    private func handleUnexpectedStop(of stoppedStream: SCStream, error: Error) {
        guard stream === stoppedStream else { return }

        lifecycleRevision &+= 1
        stream = nil
        display = nil
        streamConfiguration = nil
        stateLock.withLock {
            acceptsFrames = false
            _currentFrame = nil
            _lastError = error
            frameHandler = nil
            latestProcessor = nil
            activeStreamIdentifier = nil
            isStopping = false
        }
        try? stoppedStream.removeStreamOutput(self, type: .screen)
        transition(to: .captureFailed, error: error)
        stateLock.withLock {
            stateHandler = nil
        }
    }

    @MainActor
    private func makeConfiguration(
        for regions: CaptureRegions,
        display: SCDisplay
    ) throws -> SCStreamConfiguration {
        guard let sourceRect = regions.sourceRect() else {
            throw ScreenCaptureServiceError.noRegionsConfigured
        }

        let displaySize = CGSize(width: display.width, height: display.height)
        let invalidKinds = regions.invalidKinds(for: displaySize)
        let sourceIsContained = CGRect(origin: .zero, size: displaySize).contains(sourceRect)
        guard invalidKinds.isEmpty, sourceIsContained else {
            let reportedKinds = invalidKinds.isEmpty
                ? CaptureRegionKind.allCases.filter { regions[$0] != nil }
                : invalidKinds
            throw ScreenCaptureServiceError.invalidRegions(reportedKinds)
        }

        let scale = backingScaleFactor(for: display)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int(ceil(sourceRect.width * scale)))
        configuration.height = max(1, Int(ceil(sourceRect.height * scale)))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 2
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = false
        configuration.captureResolution = .best
        return configuration
    }

    @MainActor
    private func backingScaleFactor(for display: SCDisplay) -> CGFloat {
        let displayID = display.displayID
        if let screen = NSScreen.screens.first(where: { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == displayID
        }) {
            return screen.backingScaleFactor
        }

        let pointWidth = max(1, CGFloat(display.width))
        return max(1, CGFloat(CGDisplayPixelsWide(displayID)) / pointWidth)
    }

    private func prepareForCapture(
        regions: CaptureRegions,
        sourceRect: CGRect,
        frameHandler: @escaping FrameHandler,
        stateHandler: StateHandler?,
        stream: SCStream
    ) -> UInt64 {
        let processor = LatestFrameProcessor<CapturedFrame>(
            queue: processingQueue,
            onDroppedFrame: { DiagnosticMetrics.shared.record(.droppedFrames) }
        ) { [weak self] frame in
            guard let self else {
                return
            }
            let handler: FrameHandler? = self.stateLock.withLock {
                guard frame.generation == self._currentGeneration else { return nil }
                return self.frameHandler
            }
            handler?(frame)
        }

        let generation: UInt64 = stateLock.withLock {
            _currentGeneration &+= 1
            _currentFrame = nil
            lastDisplayTime = 0
            _regions = regions
            _sourceRect = sourceRect
            self.frameHandler = frameHandler
            self.stateHandler = stateHandler
            acceptsFrames = true
            activeStreamIdentifier = ObjectIdentifier(stream)
            isStopping = false
            latestProcessor = processor
            return _currentGeneration
        }
        return generation
    }

    private func frameStatus(in sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
        let rawStatus = attachments.first?[.status] as? Int else {
            return nil
        }
        return SCFrameStatus(rawValue: rawStatus)
    }

    private func waitForFrame(
        generation: UInt64,
        timeout: TimeInterval
    ) async throws -> CapturedFrame {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            let waiter = FrameWaiter(id: id, generation: generation, continuation: continuation)
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.timeoutWaiter(id: id)
            }
            waiter.timeoutWorkItem = timeoutWorkItem
            let existingFrame: CapturedFrame? = stateLock.withLock {
                if let frame = _currentFrame, frame.generation == generation {
                    return frame
                }
                waiters[id] = waiter
                return nil
            }
            if let existingFrame {
                continuation.resume(returning: existingFrame)
                return
            }
            outputQueue.asyncAfter(deadline: .now() + max(0.01, timeout), execute: timeoutWorkItem)
        }
    }

    private func resumeWaiters(with frame: CapturedFrame) {
        let matching: [FrameWaiter] = stateLock.withLock {
            let matching = waiters.values.filter { $0.generation == frame.generation }
            for waiter in matching {
                waiters.removeValue(forKey: waiter.id)
            }
            return matching
        }

        for waiter in matching {
            waiter.timeoutWorkItem?.cancel()
            waiter.continuation.resume(returning: frame)
        }
    }

    private func timeoutWaiter(id: UUID) {
        let waiter = stateLock.withLock {
            waiters.removeValue(forKey: id)
        }
        waiter?.continuation.resume(throwing: ScreenCaptureServiceError.refreshTimedOut)
    }

    private func failAllWaiters(with error: Error) {
        let pendingWaiters: [FrameWaiter] = stateLock.withLock {
            let values = Array(waiters.values)
            waiters.removeAll()
            return values
        }
        for waiter in pendingWaiters {
            waiter.timeoutWorkItem?.cancel()
            waiter.continuation.resume(throwing: error)
        }
    }

    private func transition(to state: BotRunState, error: Error? = nil) {
        let handler: StateHandler? = stateLock.withLock {
            _runState = state
            if let error {
                _lastError = error
            }
            return stateHandler
        }
        handler?(state)
    }

    private func transitionToRunningIfStarting() {
        let handler: StateHandler? = stateLock.withLock {
            guard acceptsFrames, _runState == .starting else { return nil }
            _runState = .running
            return stateHandler
        }
        handler?(.running)
    }
}

private extension NSLock {
    @discardableResult
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
