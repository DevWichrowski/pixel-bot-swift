import Foundation
import XCTest
@testable import PixelBot

final class DiagnosticLoggerTests: XCTestCase {
    func testRotatingJSONLLog() throws {
        try it("should keep one current and one previous JSONL file") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PixelBotLogs-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let logger = PixelBotDiagnosticLogger(
                directoryURL: directory,
                maximumFileSize: 180
            )

            for value in 0..<12 {
                logger.log("test_event", fields: ["value": .integer(value)])
                logger.flush()
            }

            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            XCTAssertEqual(files, ["runtime.jsonl", "runtime.previous.jsonl"])
        }
    }
}
