import Foundation

struct HPManaFrameReadout: Sendable {
    let hp: NumericReadout
    let mana: NumericReadout
    let hpConfirmedCurrent: Int?
    let manaConfirmedCurrent: Int?
    let generation: UInt64

    var statusReading: StatusReading {
        StatusReading(
            hpCurrent: hp.state == .valid ? hpConfirmedCurrent : nil,
            hpMax: hp.state == .valid && hpConfirmedCurrent != nil ? hp.maximum : nil,
            manaCurrent: mana.state == .valid ? manaConfirmedCurrent : nil,
            manaMax: mana.state == .valid && manaConfirmedCurrent != nil ? mana.maximum : nil
        )
    }
}

struct HPFrameReadout: Sendable {
    let readout: NumericReadout
    let confirmedCurrent: Int?
    let diagnostic: RegionDiagnostic
    let generation: UInt64
}

/// Owns independent HP and mana OCR state. Vision work is expected to run off MainActor.
final class HPManaReader: @unchecked Sendable {
    private let lock = NSLock()
    private let processingLock = NSLock()
    private var hpCaptureRegion: CaptureRegion?
    private var manaCaptureRegion: CaptureRegion?
    private var expectedGeneration: UInt64 = 0
    private var hpPipeline: NumericRegionOCRPipeline
    private var manaPipeline: NumericRegionOCRPipeline
    private let diagnosticLogger: DiagnosticLogging?
    private let diagnosticStateLock = NSLock()
    private var lastLoggedIssueSignatures: [CaptureRegionKind: String] = [:]

    var debugMode = false

    init(
        mode: OCRPipelineMode = .realtime,
        hpRequiredConfirmations: Int? = nil,
        recognizerFactory: @escaping () -> OCRTextRecognizing = { VisionTextRecognizer() },
        diagnosticLogger: DiagnosticLogging? = nil
    ) {
        self.diagnosticLogger = diagnosticLogger
        hpPipeline = NumericRegionOCRPipeline(
            format: .currentAndMaximum,
            mode: mode,
            requiredConfirmations: hpRequiredConfirmations ?? (mode == .realtime ? 2 : 1),
            recognizer: recognizerFactory()
        )
        manaPipeline = NumericRegionOCRPipeline(
            format: .currentAndMaximum,
            mode: mode,
            recognizer: recognizerFactory()
        )
    }

    /// Compatibility bridge for persisted integer tuples.
    var hpRegion: (x: Int, y: Int, width: Int, height: Int)? {
        get {
            lock.withLock { hpCaptureRegion?.integerTuple }
        }
        set {
            updateSingleRegion(kind: .hp, region: newValue.flatMap(CaptureRegion.init))
        }
    }

    /// Compatibility bridge for persisted integer tuples.
    var manaRegion: (x: Int, y: Int, width: Int, height: Int)? {
        get {
            lock.withLock { manaCaptureRegion?.integerTuple }
        }
        set {
            updateSingleRegion(kind: .mana, region: newValue.flatMap(CaptureRegion.init))
        }
    }

    var isConfigured: Bool {
        lock.withLock { hpCaptureRegion != nil && manaCaptureRegion != nil }
    }

    var generation: UInt64 {
        lock.withLock { expectedGeneration }
    }

    func region(for kind: CaptureRegionKind) -> CaptureRegion? {
        lock.withLock {
            switch kind {
            case .hp: hpCaptureRegion
            case .mana: manaCaptureRegion
            case .ammo: nil
            }
        }
    }

    func setRegions(
        hp: CaptureRegion?,
        mana: CaptureRegion?,
        generation: UInt64
    ) {
        lock.withLock {
            hpCaptureRegion = hp
            manaCaptureRegion = mana
            expectedGeneration = generation
            hpPipeline.reset(configured: hp != nil)
            manaPipeline.reset(configured: mana != nil)
        }
        diagnosticStateLock.withLock {
            lastLoggedIssueSignatures.removeAll(keepingCapacity: true)
        }
    }

    /// Compatibility bridge. New call sites should pass an explicit capture generation.
    func setRegions(
        hp: (x: Int, y: Int, width: Int, height: Int)?,
        mana: (x: Int, y: Int, width: Int, height: Int)?
    ) {
        lock.withLock {
            hpCaptureRegion = hp.flatMap(CaptureRegion.init)
            manaCaptureRegion = mana.flatMap(CaptureRegion.init)
            expectedGeneration &+= 1
            hpPipeline.reset(configured: hpCaptureRegion != nil)
            manaPipeline.reset(configured: manaCaptureRegion != nil)
        }
    }

    /// Processes both regions from one frame and commits only if configuration stayed unchanged.
    func process(
        _ frame: CapturedFrame,
        now: Date? = nil,
        onHP: ((HPFrameReadout) -> Void)? = nil
    ) -> HPManaFrameReadout? {
        processingLock.lock()
        defer { processingLock.unlock() }

        let snapshot: (
            hpRegion: CaptureRegion?,
            manaRegion: CaptureRegion?,
            hpPipeline: NumericRegionOCRPipeline,
            manaPipeline: NumericRegionOCRPipeline
        )? = lock.withLock {
            guard frame.generation == expectedGeneration else { return nil }
            return (hpCaptureRegion, manaCaptureRegion, hpPipeline, manaPipeline)
        }
        guard var snapshot else { return nil }

        let hpResult: RegionOCRProcessResult?
        if let hpRegion = snapshot.hpRegion {
            hpResult = snapshot.hpPipeline.process(frame: frame, region: hpRegion, now: now)
        } else {
            snapshot.hpPipeline.reset(configured: false)
            hpResult = nil
        }

        let hpStage: HPFrameReadout? = lock.withLock {
            guard expectedGeneration == frame.generation,
                  hpCaptureRegion == snapshot.hpRegion,
                  manaCaptureRegion == snapshot.manaRegion else {
                return nil
            }
            hpPipeline = snapshot.hpPipeline
            let currentReadout = hpPipeline.readout(at: Date())
            return HPFrameReadout(
                readout: currentReadout,
                confirmedCurrent: currentReadout.state == .valid
                    ? hpResult?.confirmedCurrent
                    : nil,
                diagnostic: hpPipeline.diagnostic(at: Date()),
                generation: frame.generation
            )
        }
        guard let hpStage else { return nil }
        logOCRResult(hpResult, kind: .hp, frame: frame, now: Date())
        onHP?(hpStage)

        let manaResult: RegionOCRProcessResult?
        if let manaRegion = snapshot.manaRegion {
            manaResult = snapshot.manaPipeline.process(frame: frame, region: manaRegion, now: now)
        } else {
            snapshot.manaPipeline.reset(configured: false)
            manaResult = nil
        }
        logOCRResult(manaResult, kind: .mana, frame: frame, now: Date())

        let completedAt = Date()
        return lock.withLock {
            guard expectedGeneration == frame.generation,
                  hpCaptureRegion == snapshot.hpRegion,
                  manaCaptureRegion == snapshot.manaRegion else {
                return nil
            }

            manaPipeline = snapshot.manaPipeline
            let hpReadout = hpPipeline.readout(at: completedAt)
            let manaReadout = manaPipeline.readout(at: completedAt)
            return HPManaFrameReadout(
                hp: hpReadout,
                mana: manaReadout,
                hpConfirmedCurrent: hpReadout.state == .valid
                    ? hpResult?.confirmedCurrent
                    : nil,
                manaConfirmedCurrent: manaReadout.state == .valid
                    ? manaResult?.confirmedCurrent
                    : nil,
                generation: frame.generation
            )
        }
    }

    func readout(for kind: CaptureRegionKind, at date: Date = Date()) -> NumericReadout {
        lock.withLock {
            switch kind {
            case .hp: hpPipeline.readout(at: date)
            case .mana: manaPipeline.readout(at: date)
            case .ammo: NumericReadout()
            }
        }
    }

    func diagnostic(for kind: CaptureRegionKind, at date: Date = Date()) -> RegionDiagnostic {
        lock.withLock {
            switch kind {
            case .hp: hpPipeline.diagnostic(at: date)
            case .mana: manaPipeline.diagnostic(at: date)
            case .ammo: RegionDiagnostic()
            }
        }
    }

    func reset(generation: UInt64? = nil) {
        lock.withLock {
            if let generation {
                expectedGeneration = generation
            } else {
                expectedGeneration &+= 1
            }
            hpPipeline.reset(configured: hpCaptureRegion != nil)
            manaPipeline.reset(configured: manaCaptureRegion != nil)
        }
        diagnosticStateLock.withLock {
            lastLoggedIssueSignatures.removeAll(keepingCapacity: true)
        }
    }

    private func updateSingleRegion(kind: CaptureRegionKind, region: CaptureRegion?) {
        lock.withLock {
            switch kind {
            case .hp:
                guard hpCaptureRegion != region else { return }
                hpCaptureRegion = region
            case .mana:
                guard manaCaptureRegion != region else { return }
                manaCaptureRegion = region
            case .ammo:
                return
            }

            expectedGeneration &+= 1
            hpPipeline.reset(configured: hpCaptureRegion != nil)
            manaPipeline.reset(configured: manaCaptureRegion != nil)
        }
    }

    private func logOCRResult(
        _ result: RegionOCRProcessResult?,
        kind: CaptureRegionKind,
        frame: CapturedFrame,
        now: Date
    ) {
        guard let result else { return }
        let frameAge = max(0, now.timeIntervalSince(frame.timestamp))
        let isSlow = result.diagnostic.latency >= 0.150
        let isOld = frameAge >= NumericRegionOCRPipeline.staleInterval
        let isInvalid = result.confirmedCurrent == nil
        let isLowConfidence = !result.wasCacheHit &&
            result.diagnostic.confidence < NumericRegionOCRPipeline.accurateFallbackThreshold
        guard isSlow || isOld || isInvalid || isLowConfidence else {
            diagnosticStateLock.withLock {
                lastLoggedIssueSignatures[kind] = nil
            }
            return
        }

        let signature = [
            result.readout.state.rawValue,
            result.diagnostic.text,
            String(isSlow),
            String(isOld),
            String(isLowConfidence),
        ].joined(separator: ":")
        let shouldLog = diagnosticStateLock.withLock { () -> Bool in
            guard lastLoggedIssueSignatures[kind] != signature else { return false }
            lastLoggedIssueSignatures[kind] = signature
            return true
        }
        guard shouldLog else { return }

        diagnosticLogger?.log("ocr_issue", fields: [
            "confidence": .double(Double(result.diagnostic.confidence)),
            "frameAgeMs": .double(frameAge * 1_000),
            "latencyMs": .double(result.diagnostic.latency * 1_000),
            "lowConfidence": .bool(isLowConfidence),
            "region": .string(kind.rawValue),
            "state": .string(result.readout.state.rawValue),
        ])
    }
}
