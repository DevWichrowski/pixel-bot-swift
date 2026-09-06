import Foundation
import XCTest
@testable import PixelBot

final class HealingControlIntegrationTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager: ConfigManager
        let keys: KeyPressService
        let bot: TibiaBot

        init(config: UserConfig = UserConfig()) {
            manager = ConfigManager(configURL: directory.appendingPathComponent("config.json"), debounceInterval: 60)
            manager.config = config
            keys = KeyPressService(eventPoster: { _, _ in true }, holdDurationProvider: { 60 }, gapDurationProvider: { 0 })
            bot = TibiaBot(configManager: manager, keyPress: keys, accessibilityChecker: { false },
                           startEventListeners: false, requestPermissionsOnInit: false)
        }

        func close() {
            keys.cancelAll()
            bot.magicShield.cancelPendingActions()
            manager.flush()
            try? FileManager.default.removeItem(at: directory)
        }

        func saved() throws -> UserConfig {
            manager.flush()
            return try JSONDecoder().decode(UserConfig.self, from: Data(contentsOf: directory.appendingPathComponent("config.json")))
        }

        func queueShield() {
            keys.resume()
            let started = DispatchSemaphore(value: 0)
            keys.pressKey("F9", priority: .regular, group: nil, validUntil: nil) { event in
                if event.phase == .keyDown { started.signal() }
            }
            _ = started.wait(timeout: .now() + 1)
            let now = Date()
            let uptime = ProcessInfo.processInfo.systemUptime
            for offset in [0.0, 0.03] {
                let timestamp = now.addingTimeInterval(offset)
                bot.magicShield.evaluate(
                    hp: NumericReadout(current: 20, maximum: 100, confidence: 1, timestamp: timestamp, state: .valid),
                    mana: NumericReadout(current: 100, maximum: 100, confidence: 1, timestamp: timestamp, state: .valid),
                    shield: ShieldReadout(current: 0, maximum: 100, confidence: 1, timestamp: timestamp, state: .inactive),
                    now: timestamp, uptime: uptime + offset)
            }
        }
    }

    @MainActor
    func testShieldHydration() {
        it("should synchronize a saved Magic Shield toggle with its feature") {
            var config = UserConfig()
            config.magicShield.enabled = true
            let f = Fixture(config: config)
            defer { f.close() }
            XCTAssertEqual([f.bot.magicShieldEnabled, f.bot.magicShield.enabled], [true, true])
        }
    }

    @MainActor
    func testShieldTogglePersistence() throws {
        for enabled in [true, false] {
            try it("should persist Magic Shield toggle set to \(enabled)") {
                let f = Fixture()
                defer { f.close() }
                f.bot.magicShieldEnabled = !enabled
                f.bot.magicShieldEnabled = enabled
                let saved = try f.saved()
                XCTAssertEqual([f.bot.magicShield.enabled, saved.magicShield.enabled], [enabled, enabled])
            }
        }
    }

    @MainActor
    func testShieldToggleKeepsObservationSeparate() {
        it("should leave observed shield capacity unchanged when enabling automation") {
            let f = Fixture()
            defer { f.close() }
            let observed = f.bot.shieldReadout.current
            f.bot.magicShieldEnabled = true
            XCTAssertEqual(f.bot.shieldReadout.current, observed)
        }
    }

    @MainActor
    func testShieldDisableCancelsQueuedActivation() {
        it("should immediately release the pending shield reservation when disabled") {
            let f = Fixture()
            defer { f.close() }
            f.bot.magicShieldEnabled = true
            f.queueShield()
            let pendingBefore = !SupportCooldown.shared.mayRequestHaste
            f.bot.magicShieldEnabled = false
            XCTAssertEqual([pendingBefore, !SupportCooldown.shared.mayRequestHaste], [true, false])
        }
    }

    @MainActor
    func testStopCancelsShieldWithoutChangingToggle() {
        it("should cancel queued shield on STOP while retaining the enabled setting") {
            let f = Fixture()
            defer { f.close() }
            f.bot.magicShieldEnabled = true
            f.queueShield()
            let pendingBefore = !SupportCooldown.shared.mayRequestHaste
            f.bot.stop()
            XCTAssertEqual([pendingBefore, !SupportCooldown.shared.mayRequestHaste,
                            f.bot.magicShieldEnabled, f.manager.config.magicShield.enabled], [true, false, true, true])
        }
    }

    @MainActor
    func testVocationSynchronizationAndPersistence() throws {
        try it("should synchronize and persist selected healing vocation") {
            let f = Fixture()
            defer { f.close() }
            f.bot.healingVocation = .druid
            let saved = try f.saved()
            XCTAssertEqual([f.bot.healer.vocation, saved.healer.vocation], [.druid, .druid])
        }
    }

    @MainActor
    func testIncompatibleSelectionPersists() throws {
        try it("should retain incompatible selected spells after changing vocation") {
            let f = Fixture()
            defer { f.close() }
            f.bot.healAction = .ultimateHealing
            f.bot.criticalAction = .restoration
            f.bot.healingVocation = .knight
            let saved = try f.saved()
            XCTAssertEqual([f.bot.healAction, f.bot.criticalAction, saved.healer.healAction, saved.healer.criticalAction],
                           [.ultimateHealing, .restoration, .ultimateHealing, .restoration])
        }
    }

    @MainActor
    func testPresetRestoresVocationAndSpells() {
        it("should restore healing vocation and selected spell identities from a preset") {
            let f = Fixture()
            defer { f.close() }
            f.bot.healingVocation = .sorcerer
            f.bot.healAction = .ultimateHealing
            f.bot.criticalAction = .restoration
            let id = f.bot.createPreset(name: "Mage")
            f.bot.healingVocation = .knight
            f.bot.healAction = .woundCleansing
            f.bot.criticalAction = .intenseWoundCleansing
            f.bot.loadPreset(id: id)
            XCTAssertTrue(f.bot.healingVocation == .sorcerer && f.bot.healer.vocation == .sorcerer
                          && f.bot.healAction == .ultimateHealing && f.bot.criticalAction == .restoration)
        }
    }

    func testLegacyConfigurationAndPresetKeepSelections() throws {
        try it("should decode older configuration and presets with all vocations and original spell identities") {
            let data = Data(#"{"healer":{"healAction":"ultimateHealing","criticalAction":"restoration"},"presets":[{"name":"Legacy","healer":{"healAction":"ultimateHealing","criticalAction":"restoration"}}]}"#.utf8)
            let config = try JSONDecoder().decode(UserConfig.self, from: data)
            XCTAssertTrue(config.healer.vocation == nil && config.presets.first?.healer.vocation == nil
                          && config.healer.healAction == .ultimateHealing && config.healer.criticalAction == .restoration
                          && config.presets.first?.healer.healAction == .ultimateHealing
                          && config.presets.first?.healer.criticalAction == .restoration)
        }
    }
}
