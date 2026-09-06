import XCTest
import AppKit
import CoreText
@testable import PixelBot

final class CaptureOCRPipelineTests: XCTestCase {
    func testWhiteTextPreprocessingRejectsGreenStatusBar() throws {
        try it("should retain white status text while rejecting the green bar") {
            let bytes: [UInt8] = [
                255, 255, 255, 255,
                0, 255, 0, 255,
            ]
            let image = CGImage(
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                ),
                provider: CGDataProvider(data: Data(bytes) as CFData)!,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!

            let result = try OCRImagePreprocessor(strategy: .whiteText).process(image)

            XCTAssertEqual([result.binaryBytes[0], result.binaryBytes[3]], [0, 255])
        }
    }

    func testWhiteTextPreprocessingRetainsAntialiasedGlyphEdges() throws {
        try it("should retain off-white glyph edges without retaining saturated status bars") {
            let bytes: [UInt8] = [
                161, 161, 161, 255,
                160, 160, 160, 255,
                0, 255, 0, 255,
                0, 0, 255, 255,
            ]
            let image = CGImage(
                width: 4,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 16,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                ),
                provider: CGDataProvider(data: Data(bytes) as CFData)!,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!

            let result = try OCRImagePreprocessor(strategy: .whiteText).process(image)

            XCTAssertEqual(
                [
                    result.binaryBytes[0],
                    result.binaryBytes[3],
                    result.binaryBytes[6],
                    result.binaryBytes[9],
                ],
                [0, 255, 255, 255]
            )
        }
    }

    func testFastRecognitionWithoutFallback() {
        it("should accept a high confidence fast result without accurate OCR") {
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10/20", confidence: 0.90)]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                mode: .realtime,
                recognizer: recognizer
            )
            let result = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0),
                region: captureOCRFullRegion()
            )

            XCTAssertEqual([result.confirmedCurrent, recognizer.calls.count], [10, 1])
        }
    }

    func testAccurateFallbackForLowConfidence() {
        it("should use accurate OCR when fast confidence is below the threshold") {
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10/20", confidence: 0.59)],
                accurate: [captureOCRCandidate("11/20", confidence: 0.92)]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                mode: .diagnostic,
                recognizer: recognizer
            )
            let result = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0),
                region: captureOCRFullRegion()
            )

            XCTAssertEqual(
                [result.confirmedCurrent, recognizer.calls.count],
                [11, 2]
            )
        }
    }

    func testAccurateFallbackForInvalidFastResult() {
        it("should use accurate OCR when fast OCR has no full valid result") {
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10")],
                accurate: [captureOCRCandidate("10/20")]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                mode: .diagnostic,
                recognizer: recognizer
            )
            let result = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0),
                region: captureOCRFullRegion()
            )

            XCTAssertEqual(
                [result.confirmedCurrent, recognizer.calls.count],
                [10, 2]
            )
        }
    }

    func testRealtimeAcceptsLowConfidenceFastResult() {
        it("should immediately accept a valid low confidence fast result in realtime mode") {
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10/20", confidence: 0.20)],
                accurate: [captureOCRCandidate("11/20", confidence: 0.99)]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                mode: .realtime,
                recognizer: recognizer
            )

            let result = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0),
                region: captureOCRFullRegion()
            )

            XCTAssertEqual([result.confirmedCurrent, recognizer.calls.count], [10, 1])
        }
    }

    func testRealtimeUsesRawAccurateFallbackForInvalidFastResult() {
        it("should use raw accurate OCR after invalid fast OCR on a Retina frame") {
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10")],
                accurate: [captureOCRCandidate("10/20")]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                mode: .realtime,
                recognizer: recognizer
            )

            let result = pipeline.process(
                frame: makeCaptureOCRFrame(
                    pattern: 0,
                    width: 24,
                    height: 12,
                    sourceRect: CGRect(x: 0, y: 0, width: 12, height: 6)
                ),
                region: captureOCRFullRegion()
            )

            XCTAssertEqual(
                ["current:\(result.confirmedCurrent ?? -1)"] + recognizer.requests,
                ["current:10", "fast:72x36", "accurate:24x12"]
            )
        }
    }

    func testRealtimeRawFallbackStillRequiresTwoMatchingReads() {
        it("should require two matching realtime reads when raw accurate OCR is needed") {
            let timestamp = Date(timeIntervalSince1970: 900)
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10"), captureOCRCandidate("10")],
                accurate: [captureOCRCandidate("10/20"), captureOCRCandidate("10/20")]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                mode: .realtime,
                requiredConfirmations: 2,
                recognizer: recognizer
            )

            let first = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0, timestamp: timestamp),
                region: captureOCRFullRegion(),
                now: timestamp
            )
            let second = pipeline.process(
                frame: makeCaptureOCRFrame(
                    pattern: 0,
                    timestamp: timestamp.addingTimeInterval(0.030)
                ),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.030)
            )

            XCTAssertEqual(
                [
                    "first:\(first.confirmedCurrent ?? -1)",
                    "second:\(second.confirmedCurrent ?? -1)",
                ] + recognizer.requests,
                [
                    "first:-1",
                    "second:10",
                    "fast:36x18",
                    "accurate:12x6",
                    "fast:36x18",
                    "accurate:12x6",
                ]
            )
        }
    }

    func testRealtimeRawFallbackRespectsFreshnessBoundary() {
        it("should reject raw accurate OCR exactly at the 250 millisecond boundary") {
            let timestamp = Date(timeIntervalSince1970: 950)
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10")],
                accurate: [captureOCRCandidate("10/20")]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                mode: .realtime,
                recognizer: recognizer
            )

            let result = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0, timestamp: timestamp),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.250)
            )

            XCTAssertEqual(
                ["current:\(result.confirmedCurrent ?? -1)"] + recognizer.requests,
                ["current:-1", "fast:36x18", "accurate:12x6"]
            )
        }
    }

    func testRealtimeSingleValueKeepsFastOnlyRecognition() {
        it("should keep single value realtime OCR on the fast preprocessed path") {
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("ammo")],
                accurate: [captureOCRCandidate("42")]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .singleValue,
                configured: true,
                mode: .realtime,
                recognizer: recognizer
            )

            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0),
                region: captureOCRFullRegion()
            )

            XCTAssertEqual(recognizer.requests, ["fast:36x18"])
        }
    }

    func testStaleFrameHasNoConfirmedValue() {
        it("should not confirm HP from a frame older than 250 milliseconds") {
            let timestamp = Date(timeIntervalSince1970: 1_000)
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("10/20")])
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                recognizer: recognizer
            )

            let result = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0, timestamp: timestamp),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.250)
            )

            XCTAssertNil(result.confirmedCurrent)
        }
    }

    func testStaleReadingDoesNotCountTowardConfirmation() {
        it("should require two fresh reads after a stale matching HP read") {
            let timestamp = Date(timeIntervalSince1970: 1_100)
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10/20"), captureOCRCandidate("10/20")]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                requiredConfirmations: 2,
                recognizer: recognizer
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0, timestamp: timestamp),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.250)
            )
            let freshResult = pipeline.process(
                frame: makeCaptureOCRFrame(
                    pattern: 1,
                    timestamp: timestamp.addingTimeInterval(0.260)
                ),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.260)
            )

            XCTAssertNil(freshResult.confirmedCurrent)
        }
    }

    func testThrownRecognitionDoesNotCountTowardConfirmation() {
        it("should require two matching reads after an OCR error") {
            let timestamp = Date(timeIntervalSince1970: 1_200)
            let recognizer = CaptureOCRThrowingRecognizerStub()
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                requiredConfirmations: 2,
                recognizer: recognizer
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0, timestamp: timestamp),
                region: captureOCRFullRegion(),
                now: timestamp
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(
                    pattern: 1,
                    timestamp: timestamp.addingTimeInterval(0.030)
                ),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.030)
            )
            let resultAfterError = pipeline.process(
                frame: makeCaptureOCRFrame(
                    pattern: 2,
                    timestamp: timestamp.addingTimeInterval(0.060)
                ),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.060)
            )

            XCTAssertNil(resultAfterError.confirmedCurrent)
        }
    }

    func testInvalidReadingBreaksAnEstablishedConfirmation() {
        it("should require two fresh reads after invalid OCR interrupts a confirmed value") {
            let timestamp = Date(timeIntervalSince1970: 1_300)
            let recognizer = CaptureOCRRecognizerStub(
                fast: [
                    captureOCRCandidate("10/20"),
                    captureOCRCandidate("10/20"),
                    [],
                    captureOCRCandidate("10/20"),
                ]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                requiredConfirmations: 2,
                recognizer: recognizer
            )
            for (pattern, offset) in [(0, 0.000), (1, 0.030), (2, 0.060)] {
                _ = pipeline.process(
                    frame: makeCaptureOCRFrame(
                        pattern: pattern,
                        timestamp: timestamp.addingTimeInterval(offset)
                    ),
                    region: captureOCRFullRegion(),
                    now: timestamp.addingTimeInterval(offset)
                )
            }
            let firstFreshResult = pipeline.process(
                frame: makeCaptureOCRFrame(
                    pattern: 0,
                    timestamp: timestamp.addingTimeInterval(0.090)
                ),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.090)
            )

            XCTAssertNil(firstFreshResult.confirmedCurrent)
        }
    }

    func testReadoutBecomingStaleDuringRecognitionBreaksConfirmation() {
        it("should require two reads when the previous confirmation expires during OCR") {
            let callCount = CaptureOCRLockedBox(0)
            let recognizer = CaptureOCRRecognizerStub(
                fast: [
                    captureOCRCandidate("10/20"),
                    captureOCRCandidate("10/20"),
                    captureOCRCandidate("10/20"),
                ],
                beforeResponse: { _ in
                    let currentCall = callCount.value + 1
                    callCount.set(currentCall)
                    if currentCall == 3 {
                        Thread.sleep(forTimeInterval: 0.100)
                    }
                }
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                requiredConfirmations: 2,
                recognizer: recognizer
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0),
                region: captureOCRFullRegion()
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 1),
                region: captureOCRFullRegion()
            )
            Thread.sleep(forTimeInterval: 0.180)
            let result = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 2),
                region: captureOCRFullRegion()
            )

            XCTAssertNil(result.confirmedCurrent)
        }
    }

    func testFreshnessBoundary() {
        it("should become stale exactly at the 250 millisecond boundary") {
            let timestamp = Date(timeIntervalSince1970: 1_000)
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("10/20")])
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                recognizer: recognizer
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0, timestamp: timestamp),
                region: captureOCRFullRegion(),
                now: timestamp
            )

            XCTAssertEqual(
                [
                    pipeline.readout(at: timestamp.addingTimeInterval(0.249)).state,
                    pipeline.readout(at: timestamp.addingTimeInterval(0.250)).state,
                ],
                [.valid, .stale]
            )
        }
    }

    func testMaximumChangeConfirmation() {
        it("should accept a changed maximum after two consecutive matching reads") {
            let timestamp = Date(timeIntervalSince1970: 2_000)
            let recognizer = CaptureOCRRecognizerStub(
                fast: [
                    captureOCRCandidate("90/100"),
                    captureOCRCandidate("90/120"),
                ]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                recognizer: recognizer
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0, timestamp: timestamp),
                region: captureOCRFullRegion(),
                now: timestamp
            )
            let initial = pipeline.readout(at: timestamp).maximum
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 1, timestamp: timestamp.addingTimeInterval(0.03)),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.03)
            )
            let afterFirstChange = pipeline.readout(at: timestamp.addingTimeInterval(0.03)).maximum
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 1, timestamp: timestamp.addingTimeInterval(0.06)),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.06)
            )
            let afterConfirmation = pipeline.readout(at: timestamp.addingTimeInterval(0.06)).maximum

            XCTAssertEqual([initial, afterFirstChange, afterConfirmation], [100, 100, 120])
        }
    }

    func testFailedOCRDoesNotPoisonHashCache() {
        it("should retry Vision when the same changed image failed previously") {
            let recognizer = CaptureOCRRecognizerStub(
                fast: [captureOCRCandidate("10/20"), [], []],
                accurate: [[], []]
            )
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                mode: .diagnostic,
                recognizer: recognizer
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0),
                region: captureOCRFullRegion()
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 1),
                region: captureOCRFullRegion()
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 1),
                region: captureOCRFullRegion()
            )

            XCTAssertEqual(recognizer.calls, [.fast, .fast, .accurate, .fast, .accurate])
        }
    }

    func testIdenticalImageCache() {
        it("should refresh an identical accepted image without another Vision request") {
            let timestamp = Date(timeIntervalSince1970: 3_000)
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("10/20")])
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                recognizer: recognizer
            )
            _ = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0, timestamp: timestamp),
                region: captureOCRFullRegion(),
                now: timestamp
            )
            let result = pipeline.process(
                frame: makeCaptureOCRFrame(
                    pattern: 0,
                    timestamp: timestamp.addingTimeInterval(0.1)
                ),
                region: captureOCRFullRegion(),
                now: timestamp.addingTimeInterval(0.1)
            )

            XCTAssertEqual([result.confirmedCurrent, recognizer.calls.count], [10, 1])
        }
    }

    func testDiagnosticImages() {
        it("should retain only region-sized raw and binary diagnostics in memory") {
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("10/20")])
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                recognizer: recognizer
            )
            let result = pipeline.process(
                frame: makeCaptureOCRFrame(pattern: 0),
                region: captureOCRFullRegion()
            )

            XCTAssertEqual(
                [
                    result.diagnostic.rawImage?.width,
                    result.diagnostic.binaryImage?.width,
                ],
                [12, 36]
            )
        }
    }

    func testSyntheticDigitFixturesAtOneAndTwoTimesScale() {
        it("should preprocess synthetic digit fixtures captured at one-times and two-times scale") {
            let oneTimes = makeSyntheticDigitFrame(scale: 1)
            let twoTimes = makeSyntheticDigitFrame(scale: 2)
            var oneTimesPipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                recognizer: CaptureOCRRecognizerStub(fast: [captureOCRCandidate("12/34")])
            )
            var twoTimesPipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                recognizer: CaptureOCRRecognizerStub(fast: [captureOCRCandidate("12/34")])
            )
            let oneTimesResult = oneTimesPipeline.process(
                frame: oneTimes.frame,
                region: oneTimes.region
            )
            let twoTimesResult = twoTimesPipeline.process(
                frame: twoTimes.frame,
                region: twoTimes.region
            )

            XCTAssertEqual(
                [
                    oneTimesResult.diagnostic.rawImage?.width,
                    oneTimesResult.diagnostic.binaryImage?.width,
                    twoTimesResult.diagnostic.rawImage?.width,
                    twoTimesResult.diagnostic.binaryImage?.width,
                ],
                [19, 57, 38, 114]
            )
        }
    }

    func testIdenticalFrameCachePerformance() {
        it("should process one hundred identical frames with cache p95 below ten milliseconds") {
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("10/20")])
            var pipeline = NumericRegionOCRPipeline(
                format: .currentAndMaximum,
                configured: true,
                recognizer: recognizer
            )
            let frame = makeCaptureOCRFrame(pattern: 0)
            var latencies: [TimeInterval] = []
            latencies.reserveCapacity(100)
            for _ in 0..<100 {
                let result = pipeline.process(frame: frame, region: captureOCRFullRegion())
                latencies.append(result.readout.latency)
            }
            let sortedCachedLatencies = latencies.dropFirst().sorted()
            let percentileIndex = Int(Double(sortedCachedLatencies.count - 1) * 0.95)
            let cacheP95 = sortedCachedLatencies[percentileIndex]

            XCTAssertTrue(
                latencies[0] < 0.100
                    && cacheP95 < 0.010
                    && recognizer.calls == [.fast]
            )
        }
    }
    func testShieldPipelineReportsActiveCapacity() {
        it("should expose active shield capacity from the production mana pipeline") {
            let now = Date()
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("1913/2790 (1633/1633)")])
            var pipeline = NumericRegionOCRPipeline(format: .manaAndShield, configured: true, recognizer: recognizer)
            _ = pipeline.process(frame: makeCaptureOCRFrame(pattern: 0, timestamp: now), region: captureOCRFullRegion(), now: now)
            XCTAssertEqual(pipeline.shield, ShieldReadout(current: 1633, maximum: 1633, confidence: 0.9, timestamp: now, state: .active))
        }
    }

    func testShieldFailureInvalidatesPreviousInactivity() {
        it("should invalidate shield evidence when the next frame is unreadable") {
            let now = Date()
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("1915/2790 (0/0)"), captureOCRCandidate("1913/2790 (?")])
            var pipeline = NumericRegionOCRPipeline(format: .manaAndShield, configured: true, recognizer: recognizer)
            _ = pipeline.process(frame: makeCaptureOCRFrame(pattern: 0, timestamp: now), region: captureOCRFullRegion(), now: now)
            _ = pipeline.process(frame: makeCaptureOCRFrame(pattern: 1, timestamp: now.addingTimeInterval(0.01)), region: captureOCRFullRegion(), now: now.addingTimeInterval(0.01))
            XCTAssertEqual(pipeline.shield.state, .unknown)
        }
    }

    func testRightHandShieldCannotBecomeMana() {
        it("should reject a right-hand shield observation lacking its parentheses") {
            let candidate = OCRTextCandidate(text: "1633/1633", confidence: 1, bounds: CGRect(x: 0.6, y: 0, width: 0.3, height: 0.8))
            let recognizer = CaptureOCRRecognizerStub(fast: [[candidate]])
            var pipeline = NumericRegionOCRPipeline(format: .manaAndShield, configured: true, recognizer: recognizer)
            let result = pipeline.process(frame: makeCaptureOCRFrame(pattern: 0), region: captureOCRFullRegion())
            XCTAssertNil(result.confirmedCurrent)
        }
    }
    func testSyntheticManaImagesThroughVision() throws {
        try it("should recognize separate mana and shield fields in synthetic white-text images") {
            let inputs = ["1915/2790 (0/0)", "1913/2790 (1633/1633)"]
            let values = try inputs.map { text -> ParsedManaReadout? in
                let context = try XCTUnwrap(CGContext(data: nil, width: 360, height: 44,
                    bitsPerComponent: 8, bytesPerRow: 360 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(CGColor(gray: 0.08, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 360, height: 44))
                // A colored shield-like icon is deliberately excluded by the white mask.
                context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.9, alpha: 1))
                context.fillEllipse(in: CGRect(x: 5, y: 11, width: 14, height: 20))
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular),
                    .foregroundColor: NSColor.white
                ])
                context.textPosition = CGPoint(x: 25, y: 12)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
                let raw = try XCTUnwrap(context.makeImage())
                let mask = try OCRImagePreprocessor(strategy: .whiteText).process(raw)
                let candidates = try VisionTextRecognizer().recognize(in: mask.image, mode: .accurate)
                return candidates.map { ManaOCRParser().parse($0.text) }.first { $0.mana != nil && $0.shield != nil }
            }
            XCTAssertEqual(values, [
                ParsedManaReadout(mana: ParsedNumericValue(current: 1915, maximum: 2790), shield: ParsedNumericValue(current: 0, maximum: 0)),
                ParsedManaReadout(mana: ParsedNumericValue(current: 1913, maximum: 2790), shield: ParsedNumericValue(current: 1633, maximum: 1633))
            ])
        }
    }

    func testAccurateShieldCompletesMatchingMana() {
        it("should retain readable accurate shield evidence when matching fast mana has higher confidence") {
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("1913/2790", confidence: 1)],
                                                      accurate: [captureOCRCandidate("1913/2790 (1633/1633)", confidence: 0.8)])
            var pipeline = NumericRegionOCRPipeline(format: .manaAndShield, configured: true, recognizer: recognizer)
            _ = pipeline.process(frame: makeCaptureOCRFrame(pattern: 0), region: captureOCRFullRegion())
            XCTAssertEqual(pipeline.shield.state, .active)
        }
    }

    func testConflictingManaMakesShieldUnknown() {
        it("should suppress shield evidence when recognition modes disagree on mana") {
            let recognizer = CaptureOCRRecognizerStub(fast: [captureOCRCandidate("1913/2790", confidence: 1)],
                                                      accurate: [captureOCRCandidate("1915/2790 (0/0)", confidence: 0.8)])
            var pipeline = NumericRegionOCRPipeline(format: .manaAndShield, configured: true, recognizer: recognizer)
            _ = pipeline.process(frame: makeCaptureOCRFrame(pattern: 0), region: captureOCRFullRegion())
            XCTAssertEqual(pipeline.shield.state, .unknown)
        }
    }

    func testConflictingShieldAlternativesRemainUnknown() {
        it("should suppress contradictory shield capacities even when mana agrees") {
            let recognizer = CaptureOCRRecognizerStub(fast: [[
                OCRTextCandidate(text: "1913/2790 (0/0)", confidence: 1),
                OCRTextCandidate(text: "1913/2790 (1633/1633)", confidence: 0.8)
            ]])
            var pipeline = NumericRegionOCRPipeline(format: .manaAndShield, configured: true, recognizer: recognizer)
            _ = pipeline.process(frame: makeCaptureOCRFrame(pattern: 0), region: captureOCRFullRegion())
            XCTAssertEqual(pipeline.shield.state, .unknown)
        }
    }

}

private enum CaptureOCRThrownError: Error {
    case recognitionFailed
}

private final class CaptureOCRThrowingRecognizerStub: OCRTextRecognizing {
    private var callCount = 0

    func recognize(in image: CGImage, mode: OCRRecognitionMode) throws -> [OCRTextCandidate] {
        _ = image
        _ = mode
        callCount += 1
        if callCount == 2 {
            throw CaptureOCRThrownError.recognitionFailed
        }
        return captureOCRCandidate("10/20")
    }
}
