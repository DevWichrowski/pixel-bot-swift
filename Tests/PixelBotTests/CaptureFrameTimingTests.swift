import XCTest
@testable import PixelBot

final class CaptureFrameTimingTests: XCTestCase {
    func testDelayedCallback() {
        it("should retain capture age instead of restarting freshness at callback arrival") {
            let capture = CaptureFrameTiming.captureUptime(
                displayTime: 1_000,
                currentTicks: 1_300,
                currentUptime: 20,
                secondsPerTick: 0.001
            )
            XCTAssertEqual(capture, 19.7)
        }
    }

    func testTimebaseConversion() {
        it("should convert mach ticks using the supplied timebase") {
            let capture = CaptureFrameTiming.captureUptime(
                displayTime: 1_000,
                currentTicks: 7_000,
                currentUptime: 20,
                secondsPerTick: 1.0 / 24_000
            )
            XCTAssertEqual(capture, 19.75)
        }
    }

    func testFutureFrameRejected() {
        it("should reject a display time later than the current clock") {
            XCTAssertNil(CaptureFrameTiming.captureUptime(displayTime: 11, currentTicks: 10, secondsPerTick: 0.1))
        }
    }

    func testScheduledDisplayFrame() {
        it("should accept a complete frame scheduled six milliseconds after callback without extending freshness") {
            XCTAssertEqual(CaptureFrameTiming.captureUptime(displayTime: 1006, currentTicks: 1000,
                currentUptime: 20, secondsPerTick: 0.001), 20)
        }
    }

    func testAbsentDisplayTimeRejected() {
        it("should reject a missing display time instead of making it fresh") {
            XCTAssertNil(CaptureFrameTiming.captureUptime(displayTime: 0, currentTicks: 10))
        }
    }

    func testDroppedPendingFrameMetric() throws {
        try it("should count only a pending frame replaced by a newer frame") {
            let queue = DispatchQueue(label: "CaptureFrameTimingTests.drop")
            queue.suspend()
            let metrics = DiagnosticMetrics()
            let processor = LatestFrameProcessor<Int>(
                queue: queue,
                onDroppedFrame: { metrics.record(.droppedFrames) },
                handler: { _ in }
            )
            processor.submit(1)
            processor.submit(2)
            processor.submit(3)
            processor.stop()
            queue.resume()
            let data = try JSONEncoder().encode(metrics.snapshot())
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertEqual(result?["droppedFrames"] as? Int, 1)
        }
    }
}
