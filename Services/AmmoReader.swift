import Foundation

struct AmmoFrameReadout: Sendable {
    let readout: NumericReadout
    let confirmedCurrent: Int?
    let generation: UInt64
}

final class AmmoReader: @unchecked Sendable {
    private let lock = NSLock()
    private let processingLock = NSLock()
    private var captureRegion: CaptureRegion?
    private var expectedGeneration: UInt64 = 0
    private var pipeline: NumericRegionOCRPipeline
    private var pendingDecreaseEvents = 0

    var debugMode = false

    init(
        mode: OCRPipelineMode = .realtime,
        recognizer: OCRTextRecognizing = VisionTextRecognizer()
    ) {
        pipeline = NumericRegionOCRPipeline(
            format: .singleValue,
            mode: mode,
            recognizer: recognizer
        )
    }

    var generation: UInt64 {
        lock.withLock { expectedGeneration }
    }

    func region() -> CaptureRegion? {
        lock.withLock { captureRegion }
    }

    func setRegion(_ region: CaptureRegion?, generation: UInt64) {
        lock.withLock {
            captureRegion = region
            expectedGeneration = generation
            pendingDecreaseEvents = 0
            pipeline.reset(configured: region != nil)
        }
    }

    /// Compatibility bridge for persisted integer tuples.
    func setRegion(_ region: (x: Int, y: Int, width: Int, height: Int)) {
        lock.withLock {
            captureRegion = CaptureRegion(region)
            expectedGeneration &+= 1
            pendingDecreaseEvents = 0
            pipeline.reset(configured: captureRegion != nil)
        }
    }

    func hasValidRegion() -> Bool {
        lock.withLock { captureRegion != nil }
    }

    /// Commits only if region and generation did not change while Vision was running.
    func process(_ frame: CapturedFrame, now: Date = Date()) -> AmmoFrameReadout? {
        processingLock.lock()
        defer { processingLock.unlock() }

        let snapshot: (region: CaptureRegion, pipeline: NumericRegionOCRPipeline)? = lock.withLock {
            guard frame.generation == expectedGeneration, let captureRegion else { return nil }
            return (captureRegion, pipeline)
        }
        guard var snapshot else { return nil }

        let previousCurrent = snapshot.pipeline.readout(at: now).current
        let result = snapshot.pipeline.process(frame: frame, region: snapshot.region, now: now)

        return lock.withLock {
            guard expectedGeneration == frame.generation,
                  captureRegion == snapshot.region else {
                return nil
            }

            pipeline = snapshot.pipeline
            if let previousCurrent,
               let confirmedCurrent = result.confirmedCurrent,
               confirmedCurrent < previousCurrent {
                pendingDecreaseEvents += 1
            }

            return AmmoFrameReadout(
                readout: pipeline.readout(at: now),
                confirmedCurrent: result.confirmedCurrent,
                generation: frame.generation
            )
        }
    }

    func readout(at date: Date = Date()) -> NumericReadout {
        lock.withLock { pipeline.readout(at: date) }
    }

    func diagnostic(at date: Date = Date()) -> RegionDiagnostic {
        lock.withLock { pipeline.diagnostic(at: date) }
    }

    /// Returns one pending edge event and removes exactly that event.
    func consumeDecreaseEvent() -> Bool {
        lock.withLock {
            guard pendingDecreaseEvents > 0 else { return false }
            pendingDecreaseEvents -= 1
            return true
        }
    }

    /// Compatibility name. Unlike the old level check, this consumes the event.
    func checkAmmoDecrease() -> Bool {
        consumeDecreaseEvent()
    }

    func reset(generation: UInt64? = nil) {
        lock.withLock {
            if let generation {
                expectedGeneration = generation
            } else {
                expectedGeneration &+= 1
            }
            pendingDecreaseEvents = 0
            pipeline.reset(configured: captureRegion != nil)
        }
    }

    func clearRegion(generation: UInt64? = nil) {
        lock.withLock {
            captureRegion = nil
            if let generation {
                expectedGeneration = generation
            } else {
                expectedGeneration &+= 1
            }
            pendingDecreaseEvents = 0
            pipeline.reset(configured: false)
        }
    }
}
