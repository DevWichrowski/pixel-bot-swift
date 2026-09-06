import Foundation
import CoreGraphics
import XCTest
@testable import PixelBot

final class ControlConfigurationTests: XCTestCase {
    func testLegacyShieldDisabled() throws {
        try it("should keep Magic Shield disabled in older configuration") {
            let config = try JSONDecoder().decode(UserConfig.self, from: Data("{}".utf8))
            XCTAssertFalse(config.magicShield.enabled)
        }
    }

    func testShieldPresetRoundTrip() throws {
        try it("should preserve Magic Shield settings in presets") {
            var config = UserConfig()
            config.magicShield.enabled = true
            config.magicShield.threshold = 20
            let preset = PresetConfig.fromConfig(config, name: "Shield")
            let decoded = try JSONDecoder().decode(PresetConfig.self, from: JSONEncoder().encode(preset))
            config.applyPreset(decoded)
            XCTAssertEqual(config.magicShield.threshold, 20)
        }
    }

    func testInactiveMapperPassesThrough() {
        it("should pass middle clicks through while mapping is disabled") {
            let service = KeyPressService(eventPoster: { _, _ in true })
            let mapper = MiddleMouseKeyMapper(keyPress: service)
            XCTAssertFalse(mapper.handleMouseEvent(type: .otherMouseDown, buttonNumber: 2))
        }
    }

    func testUnfocusedMapperPassesThrough() {
        it("should pass middle clicks through outside the selected client") {
            let service = KeyPressService(eventPoster: { _, _ in true })
            let mapper = MiddleMouseKeyMapper(keyPress: service)
            mapper.enabled = true
            mapper.inputAllowed = { false }
            XCTAssertFalse(mapper.handleMouseEvent(type: .otherMouseDown, buttonNumber: 2))
        }
    }

    func testFlushPendingConfiguration() throws {
        try it("should synchronously persist the latest configuration on shutdown") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("config.json")
            let manager = ConfigManager(configURL: url, debounceInterval: 60)
            manager.config.magicShield.threshold = 18
            manager.save()
            manager.flush()
            let saved = try JSONDecoder().decode(UserConfig.self, from: Data(contentsOf: url))
            XCTAssertEqual(saved.magicShield.threshold, 18)
        }
    }
}
