import Foundation
import CoreGraphics
import Carbon.HIToolbox

struct KeyPressRequestGroup: Hashable {
    private let id = UUID()
}

enum KeyPressLifecyclePhase: String, Sendable {
    case queued
    case keyDown
    case keyUp
    case cancelled
    case failed
}

enum KeyPressPriority: String, Sendable {
    case regular
    case urgent
    case healing
}

struct KeyPressLifecycleEvent: Sendable {
    let requestID: UUID
    let key: String
    let priority: KeyPressPriority
    let phase: KeyPressLifecyclePhase
    let timestamp: TimeInterval
    let queueWait: TimeInterval
    let validityRemaining: TimeInterval?
}

typealias KeyPressLifecycleHandler = @Sendable (KeyPressLifecycleEvent) -> Void

protocol KeyPressServicing: AnyObject {
    @discardableResult
    func pressKey(
        _ key: String,
        priority: KeyPressPriority,
        group: KeyPressRequestGroup?,
        validUntil: TimeInterval?,
        lifecycle: KeyPressLifecycleHandler?
    ) -> Bool

    func cancelPendingRequests(in group: KeyPressRequestGroup)
}

extension KeyPressServicing {
    @discardableResult
    func pressKey(_ key: String) -> Bool {
        pressKey(key, priority: .regular, group: nil, validUntil: nil, lifecycle: nil)
    }

    @discardableResult
    func pressKey(_ key: String, priority: KeyPressPriority) -> Bool {
        pressKey(key, priority: priority, group: nil, validUntil: nil, lifecycle: nil)
    }

    @discardableResult
    func pressKey(
        _ key: String,
        priority: KeyPressPriority,
        group: KeyPressRequestGroup?
    ) -> Bool {
        pressKey(key, priority: priority, group: group, validUntil: nil, lifecycle: nil)
    }

    @discardableResult
    func pressKey(_ key: String, urgent: Bool) -> Bool {
        pressKey(
            key,
            priority: urgent ? .urgent : .regular,
            group: nil,
            validUntil: nil,
            lifecycle: nil
        )
    }

    @discardableResult
    func pressKey(
        _ key: String,
        urgent: Bool,
        group: KeyPressRequestGroup?
    ) -> Bool {
        pressKey(
            key,
            priority: urgent ? .urgent : .regular,
            group: group,
            validUntil: nil,
            lifecycle: nil
        )
    }

    @discardableResult
    func pressKey(
        _ key: String,
        urgent: Bool,
        group: KeyPressRequestGroup?,
        validUntil: TimeInterval?,
        lifecycle: KeyPressLifecycleHandler?
    ) -> Bool {
        pressKey(
            key,
            priority: urgent ? .urgent : .regular,
            group: group,
            validUntil: validUntil,
            lifecycle: lifecycle
        )
    }
}

/// Service for simulating keyboard key presses using CGEvent.
/// Requests are serialized so callers never block while a key is being held.
class KeyPressService: KeyPressServicing {
    static let shared = KeyPressService(diagnosticLogger: PixelBotDiagnosticLogger.shared)

    typealias EventPoster = (_ keyCode: CGKeyCode, _ isKeyDown: Bool) -> Bool
    typealias DelayProvider = () -> TimeInterval

    private struct KeyRequest {
        let id: UUID
        let name: String
        let keyCode: CGKeyCode
        let priority: KeyPressPriority
        let group: KeyPressRequestGroup?
        let queuedAt: TimeInterval
        let validUntil: TimeInterval?
        let lifecycle: KeyPressLifecycleHandler?
    }

    private struct ActiveRequest {
        let request: KeyRequest
        let holdDuration: TimeInterval
        let gapDuration: TimeInterval
    }

    private struct PostKeyUpGate {
        let priority: KeyPressPriority
        let validUntil: TimeInterval
    }

    private let stateQueue = DispatchQueue(label: "com.pixelbot.key-press-service")
    private let stateQueueKey = DispatchSpecificKey<Void>()
    private let eventPoster: EventPoster
    private let healingHoldDurationProvider: DelayProvider
    private let urgentHoldDurationProvider: DelayProvider
    private let regularHoldDurationProvider: DelayProvider
    private let healingGapDurationProvider: DelayProvider
    private let urgentGapDurationProvider: DelayProvider
    private let regularGapDurationProvider: DelayProvider
    private let keyUpRetryInterval: TimeInterval
    private let diagnosticLogger: DiagnosticLogging?

    private var healingRequests: [KeyRequest] = []
    private var urgentRequests: [KeyRequest] = []
    private var regularRequests: [KeyRequest] = []
    private var activeRequest: ActiveRequest?
    private var postKeyUpGate: PostKeyUpGate?
    private var scheduledActiveTransition: DispatchWorkItem?
    private var scheduledGateTransition: DispatchWorkItem?
    private var scheduledStart: DispatchWorkItem?
    private var activeTransitionGeneration = 0
    private var gateTransitionGeneration = 0
    private var startGeneration = 0
    private var acceptsRequests = true
    private var didLogKeyUpFailure = false

    /// Persistent event source, reused across all presses for consistent state.
    private let eventSource: CGEventSource?

    init(
        eventPoster: EventPoster? = nil,
        holdDurationProvider: DelayProvider? = nil,
        gapDurationProvider: DelayProvider? = nil,
        healingHoldDurationProvider: @escaping DelayProvider = {
            KeyPressService.defaultHoldDuration(for: .healing)
        },
        urgentHoldDurationProvider: @escaping DelayProvider = {
            KeyPressService.defaultHoldDuration(for: .urgent)
        },
        regularHoldDurationProvider: @escaping DelayProvider = {
            KeyPressService.defaultHoldDuration(for: .regular)
        },
        healingGapDurationProvider: @escaping DelayProvider = {
            KeyPressService.defaultGapDuration(for: .healing)
        },
        urgentGapDurationProvider: @escaping DelayProvider = {
            KeyPressService.defaultGapDuration(for: .urgent)
        },
        regularGapDurationProvider: @escaping DelayProvider = {
            KeyPressService.defaultGapDuration(for: .regular)
        },
        keyUpRetryInterval: TimeInterval = 0.01,
        diagnosticLogger: DiagnosticLogging? = nil
    ) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0.0
        eventSource = source

        self.healingHoldDurationProvider = holdDurationProvider ?? healingHoldDurationProvider
        self.urgentHoldDurationProvider = holdDurationProvider ?? urgentHoldDurationProvider
        self.regularHoldDurationProvider = holdDurationProvider ?? regularHoldDurationProvider
        self.healingGapDurationProvider = gapDurationProvider ?? healingGapDurationProvider
        self.urgentGapDurationProvider = gapDurationProvider ?? urgentGapDurationProvider
        self.regularGapDurationProvider = gapDurationProvider ?? regularGapDurationProvider
        self.keyUpRetryInterval = max(0.001, keyUpRetryInterval)
        self.diagnosticLogger = diagnosticLogger
        self.eventPoster = eventPoster ?? { keyCode, isKeyDown in
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: isKeyDown
            ) else {
                return false
            }

            // Avoid leaking stale modifier state from combinedSessionState.
            event.flags = []
            event.post(tap: .cgSessionEventTap)
            return true
        }

        stateQueue.setSpecific(key: stateQueueKey, value: ())
    }

    static func defaultHoldDuration(for priority: KeyPressPriority) -> TimeInterval {
        switch priority {
        case .healing:
            return humanRandom(median: 0.050, spread: 0.15, min: 0.040, max: 0.060)
        case .urgent:
            return humanRandom(median: 0.055, spread: 0.20, min: 0.040, max: 0.075)
        case .regular:
            return humanRandom(median: 0.070, spread: 0.25, min: 0.040, max: 0.100)
        }
    }

    static func defaultGapDuration(for priority: KeyPressPriority) -> TimeInterval {
        switch priority {
        case .healing:
            return humanRandom(median: 0.015, spread: 0.20, min: 0.008, max: 0.025)
        case .urgent:
            return humanRandom(median: 0.025, spread: 0.25, min: 0.015, max: 0.045)
        case .regular:
            return humanRandom(median: 0.050, spread: 0.30, min: 0.030, max: 0.090)
        }
    }

    deinit {
        cancelAll()
    }

    /// Map of key names to CGKeyCode.
    private let keyCodeMap: [String: CGKeyCode] = [
        // Function keys
        "f1": CGKeyCode(kVK_F1),
        "f2": CGKeyCode(kVK_F2),
        "f3": CGKeyCode(kVK_F3),
        "f4": CGKeyCode(kVK_F4),
        "f5": CGKeyCode(kVK_F5),
        "f6": CGKeyCode(kVK_F6),
        "f7": CGKeyCode(kVK_F7),
        "f8": CGKeyCode(kVK_F8),
        "f9": CGKeyCode(kVK_F9),
        "f10": CGKeyCode(kVK_F10),
        "f11": CGKeyCode(kVK_F11),
        "f12": CGKeyCode(kVK_F12),

        // Letters
        "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B), "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D), "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H), "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N), "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P), "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T), "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V), "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),

        // Numbers
        "0": CGKeyCode(kVK_ANSI_0), "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3), "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6), "7": CGKeyCode(kVK_ANSI_7), "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),

        // Special keys
        "[": CGKeyCode(kVK_ANSI_LeftBracket),
        "]": CGKeyCode(kVK_ANSI_RightBracket),
        "space": CGKeyCode(kVK_Space),
        "return": CGKeyCode(kVK_Return),
        "escape": CGKeyCode(kVK_Escape),
        "tab": CGKeyCode(kVK_Tab),
        "shift": CGKeyCode(kVK_Shift),
    ]

    /// Enqueues a key press and returns immediately.
    /// Higher-priority pending requests are selected first, but never interrupt an active key hold.
    /// - Returns: `true` when the request was accepted, or `false` for an unknown key or while stopped.
    @discardableResult
    func pressKey(
        _ key: String,
        priority: KeyPressPriority,
        group: KeyPressRequestGroup?,
        validUntil: TimeInterval?,
        lifecycle: KeyPressLifecycleHandler?
    ) -> Bool {
        let normalizedKey = key.lowercased()
        let requestID = UUID()
        guard let keyCode = keyCodeMap[normalizedKey] else {
            print("⚠️ Unknown key: \(key)")
            emit(
                requestID: requestID,
                key: key,
                priority: priority,
                phase: .failed,
                queuedAt: ProcessInfo.processInfo.systemUptime,
                validUntil: validUntil,
                lifecycle: lifecycle
            )
            return false
        }

        return withState {
            let queuedAt = ProcessInfo.processInfo.systemUptime
            guard acceptsRequests else {
                emit(
                    requestID: requestID,
                    key: key,
                    priority: priority,
                    phase: .failed,
                    queuedAt: queuedAt,
                    validUntil: validUntil,
                    lifecycle: lifecycle
                )
                return false
            }

            let request = KeyRequest(
                id: requestID,
                name: key,
                keyCode: keyCode,
                priority: priority,
                group: group,
                queuedAt: queuedAt,
                validUntil: validUntil,
                lifecycle: lifecycle
            )
            switch priority {
            case .healing:
                healingRequests.append(request)
            case .urgent:
                urgentRequests.append(request)
            case .regular:
                regularRequests.append(request)
            }
            emit(request, phase: .queued)
            scheduleNextRequestIfNeeded()
            return true
        }
    }

    /// Removes requests belonging to one feature if they have not posted keyDown yet.
    /// The currently active key is intentionally allowed to finish.
    func cancelPendingRequests(in group: KeyPressRequestGroup) {
        withState {
            cancelRequests(in: &healingRequests) { $0.group == group }
            cancelRequests(in: &urgentRequests) { $0.group == group }
            cancelRequests(in: &regularRequests) { $0.group == group }
        }
    }

    /// Stops accepting input and removes every request that has not posted keyDown yet.
    /// Releasing an active key starts immediately and is retried after temporary posting failures.
    func cancelAll() {
        withState {
            acceptsRequests = false
            cancelRequests(in: &healingRequests) { _ in true }
            cancelRequests(in: &urgentRequests) { _ in true }
            cancelRequests(in: &regularRequests) { _ in true }
            startGeneration += 1
            scheduledStart?.cancel()
            scheduledStart = nil
            clearGate()

            if let activeRequest {
                activeTransitionGeneration += 1
                scheduledActiveTransition?.cancel()
                scheduledActiveTransition = nil
                attemptKeyUp(for: activeRequest, shouldLogHold: false)
            }
        }
    }

    /// Allows new input after `cancelAll()`.
    func resume() {
        withState {
            acceptsRequests = true
            scheduleNextRequestIfNeeded()
        }
    }

    private func scheduleNextRequestIfNeeded() {
        guard acceptsRequests,
              activeRequest == nil,
              scheduledStart == nil,
              let priority = nextPendingPriority else {
            return
        }

        if let gate = postKeyUpGate {
            let now = ProcessInfo.processInfo.systemUptime
            if now < gate.validUntil, !priority.canBypassGate(after: gate.priority) {
                scheduleGateExpiryIfNeeded(at: gate.validUntil)
                return
            }
            clearGate()
        }

        startGeneration += 1
        let generation = startGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.startGeneration == generation else { return }
            self.scheduledStart = nil
            self.beginNextRequest()
        }
        scheduledStart = workItem
        stateQueue.async(execute: workItem)
    }

    private func beginNextRequest() {
        guard acceptsRequests, activeRequest == nil else { return }

        let request: KeyRequest
        if !healingRequests.isEmpty {
            request = healingRequests.removeFirst()
        } else if !urgentRequests.isEmpty {
            request = urgentRequests.removeFirst()
        } else if !regularRequests.isEmpty {
            request = regularRequests.removeFirst()
        } else {
            return
        }

        if let validUntil = request.validUntil,
           ProcessInfo.processInfo.systemUptime >= validUntil {
            emit(request, phase: .cancelled)
            scheduleNextRequestIfNeeded()
            return
        }

        let holdDuration = max(0, holdDurationProvider(for: request.priority)())
        let gapDuration = max(0, gapDurationProvider(for: request.priority)())

        // This is intentionally the last check before posting keyDown. Equality is expired.
        if let validUntil = request.validUntil,
           ProcessInfo.processInfo.systemUptime >= validUntil {
            emit(request, phase: .cancelled)
            scheduleNextRequestIfNeeded()
            return
        }

        guard eventPoster(request.keyCode, true) else {
            print("❌ Failed to create key-down event for: \(request.name)")
            emit(request, phase: .failed)
            scheduleNextRequestIfNeeded()
            return
        }

        let activeRequest = ActiveRequest(
            request: request,
            holdDuration: holdDuration,
            gapDuration: gapDuration
        )
        self.activeRequest = activeRequest
        emit(request, phase: .keyDown)
        didLogKeyUpFailure = false
        scheduleActiveTransition(after: holdDuration) { [weak self] in
            self?.finishHold(for: activeRequest)
        }
    }

    private func finishHold(for activeRequest: ActiveRequest) {
        guard self.activeRequest?.request.id == activeRequest.request.id else { return }

        attemptKeyUp(for: activeRequest, shouldLogHold: true)
    }

    private func attemptKeyUp(for activeRequest: ActiveRequest, shouldLogHold: Bool) {
        let request = activeRequest.request
        guard self.activeRequest?.request.id == request.id else { return }

        if !eventPoster(request.keyCode, false) {
            if !didLogKeyUpFailure {
                print("❌ Failed to create key-up event for: \(request.name), retrying")
                didLogKeyUpFailure = true
            }
            scheduleActiveTransition(after: keyUpRetryInterval) { [weak self] in
                self?.attemptKeyUp(for: activeRequest, shouldLogHold: shouldLogHold)
            }
            return
        }
        self.activeRequest = nil
        if acceptsRequests {
            beginGate(after: request.priority, duration: activeRequest.gapDuration)
        }
        emit(request, phase: .keyUp)
        didLogKeyUpFailure = false

        if shouldLogHold {
            print("⌨️ Pressed key: \(request.name) (hold: \(Int(activeRequest.holdDuration * 1_000))ms)")
        }

        guard acceptsRequests else { return }
        scheduleNextRequestIfNeeded()
    }

    private var nextPendingPriority: KeyPressPriority? {
        if !healingRequests.isEmpty { return .healing }
        if !urgentRequests.isEmpty { return .urgent }
        if !regularRequests.isEmpty { return .regular }
        return nil
    }

    private func holdDurationProvider(for priority: KeyPressPriority) -> DelayProvider {
        switch priority {
        case .healing: return healingHoldDurationProvider
        case .urgent: return urgentHoldDurationProvider
        case .regular: return regularHoldDurationProvider
        }
    }

    private func gapDurationProvider(for priority: KeyPressPriority) -> DelayProvider {
        switch priority {
        case .healing: return healingGapDurationProvider
        case .urgent: return urgentGapDurationProvider
        case .regular: return regularGapDurationProvider
        }
    }

    private func beginGate(after priority: KeyPressPriority, duration: TimeInterval) {
        clearGate()
        guard duration > 0 else { return }
        postKeyUpGate = PostKeyUpGate(
            priority: priority,
            validUntil: ProcessInfo.processInfo.systemUptime + duration
        )
    }

    private func scheduleGateExpiryIfNeeded(at deadline: TimeInterval) {
        guard scheduledGateTransition == nil else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        gateTransitionGeneration += 1
        let generation = gateTransitionGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.gateTransitionGeneration == generation else { return }
            self.scheduledGateTransition = nil
            self.postKeyUpGate = nil
            self.scheduleNextRequestIfNeeded()
        }
        scheduledGateTransition = workItem
        stateQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func clearGate() {
        gateTransitionGeneration += 1
        scheduledGateTransition?.cancel()
        scheduledGateTransition = nil
        postKeyUpGate = nil
    }

    private func scheduleActiveTransition(after delay: TimeInterval, action: @escaping () -> Void) {
        activeTransitionGeneration += 1
        let generation = activeTransitionGeneration
        scheduledActiveTransition?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeTransitionGeneration == generation else { return }
            self.scheduledActiveTransition = nil
            action()
        }
        scheduledActiveTransition = workItem
        stateQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func withState<T>(_ action: () -> T) -> T {
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            return action()
        }
        return stateQueue.sync(execute: action)
    }

    private func cancelRequests(
        in requests: inout [KeyRequest],
        where shouldCancel: (KeyRequest) -> Bool
    ) {
        let cancelled = requests.filter(shouldCancel)
        requests.removeAll(where: shouldCancel)
        cancelled.forEach { emit($0, phase: .cancelled) }
    }

    private func emit(_ request: KeyRequest, phase: KeyPressLifecyclePhase) {
        emit(
            requestID: request.id,
            key: request.name,
            priority: request.priority,
            phase: phase,
            queuedAt: request.queuedAt,
            validUntil: request.validUntil,
            lifecycle: request.lifecycle
        )
    }

    private func emit(
        requestID: UUID,
        key: String,
        priority: KeyPressPriority,
        phase: KeyPressLifecyclePhase,
        queuedAt: TimeInterval,
        validUntil: TimeInterval?,
        lifecycle: KeyPressLifecycleHandler?
    ) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let validityRemaining = phase == .keyDown
            ? validUntil.map { max(0, $0 - timestamp) }
            : nil
        let event = KeyPressLifecycleEvent(
            requestID: requestID,
            key: key,
            priority: priority,
            phase: phase,
            timestamp: timestamp,
            queueWait: max(0, timestamp - queuedAt),
            validityRemaining: validityRemaining
        )
        lifecycle?(event)
        var fields: [String: DiagnosticLogValue] = [
            "key": .string(key),
            "priority": .string(priority.rawValue),
            "queueWaitMs": .double(event.queueWait * 1_000),
            "requestID": .string(requestID.uuidString),
            "meaning": .string(
                phase == .keyDown ? "input sent, cast not confirmed" : "input lifecycle"
            ),
        ]
        if let validityRemaining {
            let validityRemainingMs = validityRemaining * 1_000
            fields["validityRemainingMs"] = .double(validityRemainingMs)
            if priority == .healing {
                fields["frameToKeyDownMs"] = .double(max(0, 250 - validityRemainingMs))
            }
        }
        diagnosticLogger?.log("input_\(phase.rawValue)", fields: fields)
    }
}

private extension KeyPressPriority {
    func canBypassGate(after precedingPriority: KeyPressPriority) -> Bool {
        self == .healing || (self == .urgent && precedingPriority == .regular)
    }
}
