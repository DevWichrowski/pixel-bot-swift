import Foundation
import XCTest
@testable import PixelBot

final class ConfigTests: XCTestCase {
    func testOlderConfigurationCompatibility() throws {
        try it("should decode older JSON with defaults for newer fields") {
            let data = Data(#"{"healer":{"healEnabled":false}}"#.utf8)
            let config = try JSONDecoder().decode(UserConfig.self, from: data)

            XCTAssertEqual(config.healer.spiritPotionHotkey, "F3")
        }
    }

    func testHealingCooldownNormalization() throws {
        try it("should normalize stored and preset healing cooldowns to one second") {
            let data = Data(
                #"{"healer":{"spellCooldown":0.5},"presets":[{"name":"Old","healer":{"spellCooldown":0.9}}]}"#.utf8
            )

            let config = try JSONDecoder().decode(UserConfig.self, from: data)

            XCTAssertEqual(
                [config.healer.spellCooldown, config.presets.first?.healer.spellCooldown],
                [1.0, 1.0]
            )
        }
    }

    func testHealingCooldownRemainsCodable() throws {
        try it("should keep the legacy spellCooldown key when encoding configuration") {
            let encoded = try JSONEncoder().encode(UserConfig())
            let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            let healer = object?["healer"] as? [String: Any]

            XCTAssertEqual(healer?["spellCooldown"] as? Double, 1.0)
        }
    }

    func testSaveDebounce() {
        it("should write only the latest debounced configuration snapshot") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PixelBotTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }

            let configURL = directory.appendingPathComponent("user_config.json")
            let fileQueue = DispatchQueue(label: "com.pixelbot.tests.config-debounce")
            let didWrite = DispatchSemaphore(value: 0)
            let writeCount = LockedCounter()
            let manager = ConfigManager(
                configURL: configURL,
                debounceInterval: 0.01,
                fileQueue: fileQueue,
                writeData: { data, url in
                    writeCount.increment()
                    try data.write(to: url, options: .atomic)
                    didWrite.signal()
                }
            )

            manager.config.healer.healThreshold = 70
            manager.save()
            manager.config.healer.healThreshold = 65
            manager.save()
            _ = didWrite.wait(timeout: .now() + 1)
            fileQueue.sync {}

            XCTAssertEqual(writeCount.value, 1)
        }
    }

    func testResetCancellation() {
        it("should cancel a pending save before reset removes the file") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PixelBotTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }

            let configURL = directory.appendingPathComponent("user_config.json")
            let fileQueue = DispatchQueue(label: "com.pixelbot.tests.config-reset")
            let delayedQueueDrain = DispatchSemaphore(value: 0)
            let manager = ConfigManager(
                configURL: configURL,
                debounceInterval: 0.02,
                fileQueue: fileQueue
            )

            manager.save()
            manager.reset()
            fileQueue.asyncAfter(deadline: .now() + 0.05) {
                delayedQueueDrain.signal()
            }
            _ = delayedQueueDrain.wait(timeout: .now() + 1)

            XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
        }
    }

    @MainActor
    func testHydrationDoesNotSave() throws {
        try it("should not save configuration while TibiaBot hydrates UI state") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PixelBotTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }

            let configURL = directory.appendingPathComponent("user_config.json")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var storedConfig = UserConfig()
            storedConfig.healer.healThreshold = 63
            try JSONEncoder().encode(storedConfig).write(to: configURL, options: .atomic)

            let fileQueue = DispatchQueue(label: "com.pixelbot.tests.config-hydration")
            let queueDrained = DispatchSemaphore(value: 0)
            let writeCount = LockedCounter()
            let manager = ConfigManager(
                configURL: configURL,
                debounceInterval: 0.01,
                fileQueue: fileQueue,
                writeData: { _, _ in writeCount.increment() }
            )
            let keyPress = KeyPressService(
                eventPoster: { _, _ in true },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 }
            )
            let bot = TibiaBot(
                configManager: manager,
                keyPress: keyPress,
                accessibilityChecker: { false },
                startEventListeners: false,
                requestPermissionsOnInit: false
            )

            fileQueue.asyncAfter(deadline: .now() + 0.05) {
                queueDrained.signal()
            }
            _ = queueDrained.wait(timeout: .now() + 1)
            withExtendedLifetime(bot) {}

            XCTAssertEqual(writeCount.value, 0)
        }
    }
}
