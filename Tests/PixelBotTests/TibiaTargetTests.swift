import XCTest
@testable import PixelBot

final class TibiaTargetTests: XCTestCase {
    func testSingleClient() {
        it("should select the only client when no target is selected") {
            XCTAssertEqual(TibiaBot.resolveTibiaPID(selected: 0, available: [42]), 42)
        }
    }

    func testRestartedClient() {
        it("should replace a terminated target with the only remaining client") {
            XCTAssertEqual(TibiaBot.resolveTibiaPID(selected: 41, available: [42]), 42)
        }
    }

    func testMultipleClients() {
        it("should require a choice when several clients are available") {
            XCTAssertEqual(TibiaBot.resolveTibiaPID(selected: 0, available: [41, 42]), 0)
        }
    }

    func testPreservesSelection() {
        it("should preserve the selected client when another client launches") {
            XCTAssertEqual(TibiaBot.resolveTibiaPID(selected: 42, available: [41, 42]), 42)
        }
    }

    func testNoClients() {
        it("should clear the target when the game exits") {
            XCTAssertEqual(TibiaBot.resolveTibiaPID(selected: 42, available: []), 0)
        }
    }
}
