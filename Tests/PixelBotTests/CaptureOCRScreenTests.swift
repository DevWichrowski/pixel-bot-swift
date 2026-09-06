import XCTest
import Carbon.HIToolbox
@testable import PixelBot

final class CaptureOCRScreenTests: XCTestCase {
    private final class ProcessingProbe {
        private let lock = NSLock()
        private var active = 0
        private var maximumActive = 0
        private var values: [Int] = []

        func begin(_ value: Int) {
            lock.withLock {
                active += 1
                maximumActive = max(maximumActive, active)
                values.append(value)
            }
        }

        func end() {
            lock.withLock {
                active -= 1
            }
        }

        var result: String {
            lock.withLock { "\(values)|\(maximumActive)" }
        }
    }

    func testOneAndTwoTimesRegionTransforms() {
        it("should transform HP mana and ammo through one shared one-times and two-times mapping") {
            let source = CGRect(x: 10, y: 20, width: 100, height: 50)
            let hp = CaptureRegion(x: 10, y: 20, width: 20, height: 10)!
            let mana = CaptureRegion(x: 30, y: 25, width: 30, height: 15)!
            let ammo = CaptureRegion(x: 80, y: 50, width: 10, height: 10)!
            let regions = [hp, mana, ammo]
            let oneTimes = regions.map {
                CaptureRegionTransformer.pixelRect(
                    for: $0,
                    sourceRect: source,
                    bufferSize: CGSize(width: 100, height: 50)
                )
            }
            let twoTimes = regions.map {
                CaptureRegionTransformer.pixelRect(
                    for: $0,
                    sourceRect: source,
                    bufferSize: CGSize(width: 200, height: 100)
                )
            }

            XCTAssertEqual(
                oneTimes + twoTimes,
                [
                    CGRect(x: 0, y: 0, width: 20, height: 10),
                    CGRect(x: 20, y: 5, width: 30, height: 15),
                    CGRect(x: 70, y: 30, width: 10, height: 10),
                    CGRect(x: 0, y: 0, width: 40, height: 20),
                    CGRect(x: 40, y: 10, width: 60, height: 30),
                    CGRect(x: 140, y: 60, width: 20, height: 20),
                ]
            )
        }
    }

    func testRegionOutsideMainDisplay() {
        it("should reject a region that extends beyond the main display") {
            let region = CaptureRegion(x: 90, y: 10, width: 11, height: 10)!

            XCTAssertFalse(region.isContained(in: CGSize(width: 100, height: 100)))
        }
    }

    func testLatestFrameWins() {
        it("should process at most one frame and replace pending work with the latest frame") {
            let queue = DispatchQueue(label: "CaptureOCRScreenTests.latest")
            let firstStarted = DispatchSemaphore(value: 0)
            let releaseFirst = DispatchSemaphore(value: 0)
            let completed = DispatchSemaphore(value: 0)
            let probe = ProcessingProbe()
            let processor = LatestFrameProcessor<Int>(queue: queue) { value in
                probe.begin(value)
                if value == 1 {
                    firstStarted.signal()
                    _ = releaseFirst.wait(timeout: .now() + 1)
                }
                probe.end()
                if value == 3 {
                    completed.signal()
                }
            }

            processor.submit(1)
            _ = firstStarted.wait(timeout: .now() + 1)
            processor.submit(2)
            processor.submit(3)
            releaseFirst.signal()
            _ = completed.wait(timeout: .now() + 1)
            processor.stop()

            XCTAssertEqual(probe.result, "[1, 3]|1")
        }
    }

    func testReaderIgnoresOldGeneration() {
        it("should ignore OCR completion after region generation changes") {
            let recognitionStarted = DispatchSemaphore(value: 0)
            let releaseRecognition = DispatchSemaphore(value: 0)
            let processingCompleted = DispatchSemaphore(value: 0)
            let result = CaptureOCRLockedBox<HPManaFrameReadout?>(nil)
            let hpRecognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10/20")],
                beforeResponse: { mode in
                    guard mode == .fast else { return }
                    recognitionStarted.signal()
                    _ = releaseRecognition.wait(timeout: .now() + 1)
                }
            )
            let manaRecognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("30/40")])
            var recognizers: [OCRTextRecognizing] = [hpRecognizer, manaRecognizer]
            let reader = HPManaReader(
                hpRequiredConfirmations: 1,
                recognizerFactory: { recognizers.removeFirst() }
            )
            let hp = CaptureRegion(x: 0, y: 0, width: 6, height: 6)!
            let mana = CaptureRegion(x: 6, y: 0, width: 6, height: 6)!
            reader.setRegions(hp: hp, mana: mana, generation: 1)
            let frame = makeCaptureOCRFrame(pattern: 0, generation: 1)

            DispatchQueue.global(qos: .userInitiated).async {
                result.set(reader.process(frame))
                processingCompleted.signal()
            }
            _ = recognitionStarted.wait(timeout: .now() + 1)
            reader.setRegions(hp: hp, mana: mana, generation: 2)
            releaseRecognition.signal()
            _ = processingCompleted.wait(timeout: .now() + 1)

            XCTAssertNil(result.value)
        }
    }

    func testPerFrameConfirmation() {
        it("should expose only values confirmed in the current frame") {
            let hpRecognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10/20"), []],
                accurate: [[]]
            )
            let manaRecognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("30/40"), captureOCRCandidate("29/40")]
            )
            var recognizers: [OCRTextRecognizing] = [hpRecognizer, manaRecognizer]
            let reader = HPManaReader(
                hpRequiredConfirmations: 1,
                recognizerFactory: { recognizers.removeFirst() }
            )
            let hp = CaptureRegion(x: 0, y: 0, width: 6, height: 6)!
            let mana = CaptureRegion(x: 6, y: 0, width: 6, height: 6)!
            reader.setRegions(hp: hp, mana: mana, generation: 1)
            _ = reader.process(makeCaptureOCRFrame(pattern: 0, generation: 1))
            let result = reader.process(makeCaptureOCRFrame(pattern: 1, generation: 1))

            XCTAssertEqual(
                [result?.hpConfirmedCurrent, result?.manaConfirmedCurrent],
                [nil, 29]
            )
        }
    }

    func testHPNumericRecognitionRemainsImmediate() {
        it("should publish changing HP immediately for independent action confirmation") {
            let hpRecognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("40/100"), captureOCRCandidate("39/100")]
            )
            let manaRecognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("80/100"), captureOCRCandidate("80/100")]
            )
            var recognizers: [OCRTextRecognizing] = [hpRecognizer, manaRecognizer]
            let reader = HPManaReader(recognizerFactory: { recognizers.removeFirst() })
            let hp = CaptureRegion(x: 0, y: 0, width: 6, height: 6)!
            let mana = CaptureRegion(x: 6, y: 0, width: 6, height: 6)!
            reader.setRegions(hp: hp, mana: mana, generation: 1)

            let first = reader.process(makeCaptureOCRFrame(pattern: 0, generation: 1))
            let second = reader.process(makeCaptureOCRFrame(pattern: 1, generation: 1))

            XCTAssertEqual(
                [
                    first?.hpConfirmedCurrent,
                    second?.hpConfirmedCurrent,
                    hpRecognizer.calls.count,
                ],
                [40, 39, 2]
            )
        }
    }

    func testHPHealingPrecedesBlockedManaOCR() {
        it("should enqueue an HP heal before blocked mana OCR is released") {
            let manaStarted = DispatchSemaphore(value: 0)
            let releaseMana = DispatchSemaphore(value: 0)
            let processingCompleted = DispatchSemaphore(value: 0)
            let healingKeyDown = DispatchSemaphore(value: 0)
            let hpRecognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("40/100"), captureOCRCandidate("40/100")]
            )
            let manaCallLock = NSLock()
            var manaCallCount = 0
            let manaRecognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("80/100"), captureOCRCandidate("80/100")],
                beforeResponse: { mode in
                    guard mode == .fast else { return }
                    let shouldBlock = manaCallLock.withLock { () -> Bool in
                        manaCallCount += 1
                        return manaCallCount == 2
                    }
                    if shouldBlock {
                        manaStarted.signal()
                        _ = releaseMana.wait(timeout: .now() + 1)
                    }
                }
            )
            var recognizers: [OCRTextRecognizing] = [hpRecognizer, manaRecognizer]
            let reader = HPManaReader { recognizers.removeFirst() }
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if keyCode == CGKeyCode(kVK_F1), isKeyDown {
                        healingKeyDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 }
            )
            let healer = AutoHealer(keyPress: service, reactionDelayOverride: { 0 })
            healer.criticalHeal.enabled = false
            healer.heal.action = .salvation
            let hp = CaptureRegion(x: 0, y: 0, width: 6, height: 6)!
            let mana = CaptureRegion(x: 6, y: 0, width: 6, height: 6)!
            reader.setRegions(hp: hp, mana: mana, generation: 1)
            _ = reader.process(makeCaptureOCRFrame(pattern: 0, generation: 1))

            DispatchQueue.global(qos: .userInitiated).async {
                _ = reader.process(
                    makeCaptureOCRFrame(pattern: 1, generation: 1),
                    onHP: { stage in
                        if let maximum = stage.readout.maximum,
                           let current = stage.confirmedCurrent {
                            healer.setMaxHP(maximum)
                            healer.checkAndHeal(currentHP: current)
                        }
                    }
                )
                processingCompleted.signal()
            }
            _ = manaStarted.wait(timeout: .now() + 1)
            let result = healingKeyDown.wait(timeout: .now() + 0.5)
            releaseMana.signal()
            _ = processingCompleted.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(result, .success)
        }
    }

    func testAmmoDecreaseEventConsumption() {
        it("should emit and consume exactly one event for one accepted ammo decrease") {
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10"), captureOCRCandidate("9")]
            )
            let reader = AmmoReader(recognizer: recognizer)
            reader.setRegion(captureOCRFullRegion(), generation: 1)
            _ = reader.process(makeCaptureOCRFrame(pattern: 0, generation: 1))
            _ = reader.process(makeCaptureOCRFrame(pattern: 1, generation: 1))

            XCTAssertEqual(
                [reader.consumeDecreaseEvent(), reader.consumeDecreaseEvent()],
                [true, false]
            )
        }
    }

    func testRegionResetClearsReaderState() {
        it("should clear cached values when a region generation is reset") {
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("10")])
            let reader = AmmoReader(recognizer: recognizer)
            reader.setRegion(captureOCRFullRegion(), generation: 1)
            _ = reader.process(makeCaptureOCRFrame(pattern: 0, generation: 1))
            reader.setRegion(captureOCRFullRegion(), generation: 2)

            XCTAssertEqual(reader.readout().state, .invalid)
        }
    }
}
