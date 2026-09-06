import XCTest
@testable import PixelBot

final class InputSafeguardTests: XCTestCase {
    private final class ImmediateInput: KeyPressServicing {
        var keys: [String] = []
        var now: TimeInterval = 100
        func pressKey(_ key: String, priority: KeyPressPriority, group: KeyPressRequestGroup?,
                      validUntil: TimeInterval?, lifecycle: KeyPressLifecycleHandler?) -> Bool {
            keys.append(key)
            let id = UUID()
            for phase in [KeyPressLifecyclePhase.queued, .keyDown, .keyUp] {
                lifecycle?(KeyPressLifecycleEvent(requestID: id, key: key, priority: priority,
                    phase: phase, timestamp: now, queueWait: 0, validityRemaining: nil))
            }
            return true
        }
        func cancelPendingRequests(in group: KeyPressRequestGroup) {}
    }

    func testLegacyActionRequiresSelection() throws {
        try it("should retain legacy settings without inferring an action from the hotkey") {
            let config = try JSONDecoder().decode(HealConfig.self, from: Data(#"{"enabled":true,"threshold":75,"hotkey":"F1"}"#.utf8))
            XCTAssertTrue(config.enabled && config.action == nil && config.hotkey == "F1")
        }
    }

    func testCriticalFallback() {
        it("should use an eligible normal heal while the critical individual cooldown remains active") {
            let input = ImmediateInput()
            let healer = AutoHealer(keyPress: input, reactionDelayOverride: { 0 }, uptimeProvider: { input.now })
            healer.maxHP = 100
            healer.criticalHeal.action = .intenseWoundCleansing
            healer.heal.action = .woundCleansing
            _ = healer.checkAndHeal(currentHP: 20)
            input.now = 103
            _ = healer.checkAndHeal(currentHP: 19)
            XCTAssertEqual(input.keys, ["F2", "F1"])
        }
    }

    func testFallbackRequiresItsOwnConfirmation() {
        it("should suppress fallback when only the critical threshold is confirmed") {
            let input = ImmediateInput()
            let healer = AutoHealer(keyPress: input, reactionDelayOverride: { 0 }, uptimeProvider: { input.now })
            healer.maxHP = 100
            healer.criticalHeal.threshold = 80
            healer.criticalHeal.action = .intenseWoundCleansing
            healer.heal.action = .woundCleansing
            _ = healer.checkAndHeal(currentHP: 79)
            input.now = 103
            _ = healer.checkAndHeal(currentHP: 74, allowNormal: false)
            XCTAssertEqual(input.keys, ["F2"])
        }
    }

    func testKnightCooldown() {
        it("should retain the knight healing group cooldown for two seconds") {
            let input = ImmediateInput()
            let healer = AutoHealer(keyPress: input, reactionDelayOverride: { 0 }, uptimeProvider: { input.now })
            healer.maxHP = 100
            healer.criticalHeal.enabled = false
            healer.heal.action = .woundCleansing
            _ = healer.checkAndHeal(currentHP: 50)
            input.now = 101.5
            _ = healer.checkAndHeal(currentHP: 45)
            XCTAssertEqual(input.keys, ["F1"])
        }
    }

    func testZeroHP() {
        it("should suppress healing for zero HP") {
            let input = ImmediateInput()
            let healer = AutoHealer(keyPress: input, reactionDelayOverride: { 0 })
            healer.maxHP = 100
            healer.criticalHeal.action = .salvation
            _ = healer.checkAndHeal(currentHP: 0)
            XCTAssertTrue(input.keys.isEmpty)
        }
    }

    func testSpiritConfirmationDoesNotConfirmCriticalSpell() {
        it("should use only the confirmed potion when the critical decision has one frame") {
            let input = ImmediateInput()
            let healer = AutoHealer(keyPress: input, reactionDelayOverride: { 0 })
            healer.maxHP = 100
            healer.spiritPotionHeal = true
            healer.spiritPotionThreshold = 60
            healer.criticalHeal.action = .salvation
            healer.heal.action = .salvation
            _ = healer.checkSpiritPotionHeal(currentHP: 49, allowCritical: false, allowNormal: false, allowPotion: true)
            XCTAssertEqual(input.keys, ["F3"])
        }
    }

    func testCriticalConfirmationDoesNotRequireSpiritThreshold() {
        it("should cast a confirmed critical spell above the spirit potion threshold") {
            let input = ImmediateInput()
            let healer = AutoHealer(keyPress: input, reactionDelayOverride: { 0 })
            healer.maxHP = 100
            healer.spiritPotionHeal = true
            healer.criticalHeal.action = .salvation
            _ = healer.checkSpiritPotionHeal(currentHP: 45, allowCritical: true, allowNormal: false, allowPotion: false)
            XCTAssertEqual(input.keys, ["F2"])
        }
    }

    func testSupportCooldown() {
        it("should share Support readiness until two seconds after key down") {
            let support = SupportCooldown()
            support.recordKeyDown(at: 100)
            XCTAssertEqual([support.isReady(at: 101.99), support.isReady(at: 102)], [false, true])
        }
    }

    func testEmergencyPriority() {
        it("should dispatch emergency shield before pending healing without interrupting a held key") {
            let lock = NSLock()
            var events: [String] = []
            let blocker = DispatchSemaphore(value: 0)
            let finished = expectation(description: "finished")
            let service = KeyPressService(eventPoster: { code, down in
                lock.withLock { events.append("\(code):\(down)") }
                if code == 101, down { blocker.signal() }
                if code == 122, !down { finished.fulfill() }
                return true
            }, holdDurationProvider: { 0.03 }, gapDurationProvider: { 0 })
            service.pressKey("F9")
            _ = blocker.wait(timeout: .now() + 1)
            service.pressKey("F1", priority: .healing)
            service.pressKey("r", priority: .emergency)
            wait(for: [finished], timeout: 1)
            service.cancelAll()
            XCTAssertEqual(lock.withLock { events }, ["101:true", "101:false", "15:true", "15:false", "122:true", "122:false"])
        }
    }

    func testPreflightAtDispatch() {
        it("should cancel a request that fails dispatch validation") {
            let counter = LockedCounter()
            let service = KeyPressService(eventPoster: { _, down in
                if down { counter.increment() }
                return true
            })
            let cancelled = expectation(description: "cancelled")
            service.pressKey("r", priority: .emergency, group: nil, validUntil: nil, isValid: { false }) { event in
                if event.phase == .cancelled { cancelled.fulfill() }
            }
            wait(for: [cancelled], timeout: 1)
            service.cancelAll()
            XCTAssertEqual(counter.value, 0)
        }
    }

    func testDeadlineRecheckedAfterDispatchValidation() {
        it("should cancel input when its deadline expires during dispatch validation") {
            let counter = LockedCounter()
            let service = KeyPressService(eventPoster: { _, down in
                if down { counter.increment() }
                return true
            })
            let cancelled = expectation(description: "cancelled")
            service.pressKey(
                "r",
                priority: .emergency,
                group: nil,
                validUntil: ProcessInfo.processInfo.systemUptime + 0.02,
                isValid: {
                    Thread.sleep(forTimeInterval: 0.05)
                    return true
                }
            ) { event in
                if event.phase == .cancelled { cancelled.fulfill() }
            }
            wait(for: [cancelled], timeout: 1)
            service.cancelAll()
            XCTAssertEqual(counter.value, 0)
        }
    }
}
