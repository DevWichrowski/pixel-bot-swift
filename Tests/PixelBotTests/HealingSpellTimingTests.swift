import XCTest
@testable import PixelBot

final class HealingSpellTimingTests: XCTestCase {
    private final class PendingKeys: KeyPressServicing {
        struct Request {
            let id = UUID()
            let key: String
            let priority: KeyPressPriority
            let group: KeyPressRequestGroup?
            let validUntil: TimeInterval?
            let isValid: () -> Bool
            let lifecycle: KeyPressLifecycleHandler?
        }
        var now: TimeInterval = 100
        var requests: [Request] = []
        var sent: [String] = []
        var accepts = true
        var honorsCancellation = true

        func pressKey(_ key: String, priority: KeyPressPriority, group: KeyPressRequestGroup?,
                      validUntil: TimeInterval?, lifecycle: KeyPressLifecycleHandler?) -> Bool {
            pressKey(key, priority: priority, group: group, validUntil: validUntil,
                     isValid: { true }, lifecycle: lifecycle)
        }

        func pressKey(_ key: String, priority: KeyPressPriority, group: KeyPressRequestGroup?,
                      validUntil: TimeInterval?, isValid: @escaping () -> Bool,
                      lifecycle: KeyPressLifecycleHandler?) -> Bool {
            guard accepts else { return false }
            let request = Request(key: key, priority: priority, group: group,
                                  validUntil: validUntil, isValid: isValid, lifecycle: lifecycle)
            requests.append(request)
            emit(request, .queued)
            return true
        }

        func cancelPendingRequests(in group: KeyPressRequestGroup) {
            guard honorsCancellation else { return }
            let cancelled = requests.filter { $0.group == group }
            requests.removeAll { $0.group == group }
            cancelled.forEach { emit($0, .cancelled) }
        }

        func finish(_ phase: KeyPressLifecyclePhase = .keyDown) {
            guard !requests.isEmpty else { return }
            let request = requests.removeFirst()
            guard phase == .keyDown else { emit(request, phase); return }
            guard request.isValid(), request.validUntil.map({ now < $0 }) ?? true else {
                emit(request, .cancelled)
                return
            }
            sent.append(request.key)
            emit(request, .keyDown)
            emit(request, .keyUp)
        }

        private func emit(_ request: Request, _ phase: KeyPressLifecyclePhase) {
            request.lifecycle?(KeyPressLifecycleEvent(requestID: request.id, key: request.key,
                priority: request.priority, phase: phase, timestamp: now, queueWait: 0,
                validityRemaining: request.validUntil.map { $0 - now }))
        }
    }

    private final class Fixture {
        let keys = PendingKeys()
        let healer: AutoHealer
        init(
            normal: HealingAction = .ultimateHealing,
            critical: HealingAction = .restoration,
            reactionDelay: @escaping () -> TimeInterval = { 0 }
        ) {
            healer = AutoHealer(
                keyPress: keys,
                reactionDelayOverride: reactionDelay,
                uptimeProvider: { [keys] in keys.now }
            )
            healer.maxHP = 100
            healer.heal = HealConfig(enabled: true, threshold: 75, hotkey: "F1", action: normal)
            healer.criticalHeal = HealConfig(enabled: true, threshold: 50, hotkey: "F2", action: critical)
        }
        @discardableResult
        func heal(_ hp: Int = 20) -> String? { healer.checkAndHeal(currentHP: hp) }
        func cast(_ hp: Int = 20) { heal(hp); keys.finish() }
    }

    func testRestorationFallback() {
        it("should permit Ultimate Healing one second after Restoration") {
            let f = Fixture()
            f.cast()
            f.keys.now += 1
            XCTAssertEqual(f.heal(), "normal")
        }
    }

    func testRestorationGroupBoundaries() {
        for elapsed in [0.999, 1.0] {
            it("should enforce Restoration Healing group expiry at \(elapsed) seconds") {
                let f = Fixture()
                f.cast()
                f.keys.now += elapsed
                XCTAssertEqual(f.heal(), elapsed < 1 ? nil : "normal")
            }
        }
    }

    func testIndividualReadinessRecheckedBeforeDispatch() {
        it("should recheck individual readiness immediately before key down") {
            let f = Fixture()
            f.cast()
            f.keys.now += 6
            f.heal()
            f.keys.now = 105.999
            f.keys.finish()
            XCTAssertEqual(f.keys.sent, ["F2"])
        }
    }

    func testRestorationIndividualBoundaries() {
        for elapsed in [5.999, 6.0] {
            it("should enforce Restoration individual expiry at \(elapsed) seconds") {
                let f = Fixture()
                f.healer.heal.enabled = false
                f.cast()
                f.keys.now += elapsed
                XCTAssertEqual(f.heal(), elapsed < 6 ? nil : "critical")
            }
        }
    }

    func testKnightGroupBoundaries() {
        for elapsed in [1.999, 2.0] {
            it("should enforce knight healing group expiry at \(elapsed) seconds") {
                let f = Fixture(normal: .woundCleansing, critical: .intenseWoundCleansing)
                f.cast()
                f.keys.now += elapsed
                XCTAssertEqual(f.heal(), elapsed < 2 ? nil : "normal")
            }
        }
    }

    func testKnightIndividualBoundaries() {
        for elapsed in [119.999, 120.0] {
            it("should enforce Intense Wound Cleansing expiry at \(elapsed) seconds") {
                let f = Fixture(normal: .woundCleansing, critical: .intenseWoundCleansing)
                f.healer.heal.enabled = false
                f.cast()
                f.keys.now += elapsed
                XCTAssertEqual(f.heal(), elapsed < 120 ? nil : "critical")
            }
        }
    }

    func testIdenticalSlotsShareCooldown() {
        it("should share Restoration individual cooldown across both slots") {
            let f = Fixture(normal: .restoration)
            f.cast(60)
            f.keys.now += 1
            XCTAssertNil(f.heal())
        }
    }

    func testDispatchFailuresDoNotStartCooldown() {
        for phase in [KeyPressLifecyclePhase.failed, .cancelled] {
            it("should keep Restoration ready after \(phase.rawValue) dispatch") {
                let f = Fixture()
                f.heal()
                f.keys.finish(phase)
                XCTAssertEqual(f.heal(), "critical")
            }
        }
    }

    func testRejectedEnqueueDoesNotStartCooldown() {
        it("should release the reservation when input rejects enqueue") {
            let f = Fixture()
            f.keys.accepts = false
            f.heal()
            f.keys.accepts = true
            XCTAssertEqual(f.heal(), "critical")
        }
    }

    func testQueuedConfigurationChanges() {
        let changes: [(String, (AutoHealer) -> Void)] = [
            ("spell", { $0.criticalHeal.action = .ultimateHealing }),
            ("hotkey", { $0.criticalHeal.hotkey = "F5" }),
            ("threshold", { $0.criticalHeal.threshold = 10 }),
            ("enabled", { $0.criticalHeal.enabled = false }),
            ("vocation", { $0.vocation = .knight }),
            ("potion mode", { $0.criticalIsPotion = true }),
            ("stop", { $0.cancelPendingActions() })
        ]
        for (name, change) in changes {
            it("should immediately cancel queued healing after changing \(name)") {
                let f = Fixture()
                f.heal()
                change(f.healer)
                XCTAssertTrue(f.keys.requests.isEmpty)
            }
            it("should reject stale healing at dispatch after changing \(name)") {
                let f = Fixture()
                f.keys.honorsCancellation = false
                f.heal()
                change(f.healer)
                f.keys.finish()
                XCTAssertTrue(f.keys.sent.isEmpty)
            }
        }
    }

    func testIncompatibleCriticalFallsBack() {
        it("should preserve an incompatible critical selection while using compatible normal healing") {
            let f = Fixture(normal: .woundCleansing)
            f.healer.vocation = .knight
            XCTAssertEqual(f.heal(), "normal")
        }
    }

    func testCooldownStartsAtKeyDown() {
        it("should measure cooldown from successful key down instead of enqueue") {
            let f = Fixture()
            f.heal()
            f.keys.now += 0.2
            f.keys.finish()
            f.keys.now = 101
            XCTAssertNil(f.heal())
        }
    }

    func testGroupReadinessRecheckedBeforeDispatch() {
        it("should recheck group readiness immediately before key down") {
            let f = Fixture()
            f.cast()
            f.keys.now += 1
            f.heal()
            // A controlled clock exercises the dispatch guard independently of reservation.
            f.keys.now = 100.5
            f.keys.finish()
            XCTAssertEqual(f.keys.sent, ["F2"])
        }
    }

    func testRegenerationCannotCastAsEmergencyHeal() {
        for action in [HealingAction.recovery, .intenseRecovery] {
            it("should exclude \(action.rawValue) from emergency slots") {
                let f = Fixture(normal: action, critical: action)
                XCTAssertNil(f.heal())
            }
        }
    }

    func testConfigurationChangePreservesAttempts() {
        it("should retain the spell cooldown after changing selections away and back") {
            let f = Fixture()
            f.cast()
            f.healer.criticalHeal.action = .ultimateHealing
            f.healer.criticalHeal.action = .restoration
            f.healer.heal.enabled = false
            f.keys.now += 1
            XCTAssertNil(f.heal())
        }
    }

    func testNormalReactionDelayBoundaries() {
        for delay in [0.05, 0.15] {
            it("should wait until the (Int(delay * 1_000)) ms normal-healing deadline") {
                let f = Fixture(reactionDelay: { delay })
                let start = f.heal(60)
                f.keys.now += delay - 0.001
                let before = f.heal(60)
                f.keys.now += 0.001
                let ready = f.heal(60)
                XCTAssertEqual([start, before, ready], [nil, nil, "normal"])
            }
        }
    }

    func testNormalReactionDelayDrawsOncePerEpisode() {
        it("should keep one reaction-delay draw while HP remains below normal threshold") {
            let lock = NSLock()
            var draws = 0
            let f = Fixture(reactionDelay: {
                lock.withLock { draws += 1 }
                return 0.1
            })
            _ = f.heal(60)
            f.keys.now += 0.1
            f.cast(60)
            f.keys.now += 1
            f.cast(60)
            XCTAssertEqual(lock.withLock { draws }, 1)
        }
    }

    func testNormalReactionDelayRearmsAfterRecovery() {
        it("should draw a new delay after HP recovers to the normal threshold") {
            let lock = NSLock()
            var draws = 0
            let f = Fixture(reactionDelay: {
                lock.withLock { draws += 1 }
                return 0.1
            })
            _ = f.heal(60)
            _ = f.heal(75)
            _ = f.heal(60)
            XCTAssertEqual(lock.withLock { draws }, 2)
        }
    }

    func testNormalReactionDelayEmergencyBypass() {
        it("should bypass the delay within five percentage points of critical") {
            let f = Fixture(reactionDelay: { 0.15 })
            XCTAssertEqual(f.heal(55), "normal")
        }
    }

    func testUnavailableCriticalFallsBackWithoutReactionDelay() {
        it("should cast the normal rescue spell immediately while critical is unavailable") {
            let f = Fixture(reactionDelay: { 0.15 })
            f.cast(20)
            f.keys.now += 1
            XCTAssertEqual(f.heal(20), "normal")
        }
    }

    func testFailedNormalRequestKeepsEpisodeReady() {
        it("should retry a failed normal request without drawing another delay") {
            let lock = NSLock()
            var draws = 0
            let f = Fixture(reactionDelay: {
                lock.withLock { draws += 1 }
                return 0.1
            })
            _ = f.heal(60)
            f.keys.now += 0.1
            _ = f.heal(60)
            f.keys.finish(.failed)
            let retry = f.heal(60)
            XCTAssertTrue(retry == "normal" && lock.withLock { draws } == 1)
        }
    }

    func testRepeatedHPFrameClassification() {
        it("should reject a repeated HP frame for healing decisions") {
            XCTAssertEqual(hpFrameContinuity(previous: 10, current: 10), .repeatedOrOlder)
        }
    }

    func testInterruptedHPFrameClassification() {
        it("should interrupt an episode at a 250 ms HP frame gap") {
            XCTAssertEqual(hpFrameContinuity(previous: 10, current: 10.25), .interrupted)
        }
    }

    func testNormalReactionDelayOverlapsCooldown() {
        it("should let the episode delay elapse while the healing group is cooling down") {
            let lock = NSLock()
            var delays = [0.0, 0.1]
            let f = Fixture(reactionDelay: {
                lock.withLock { delays.removeFirst() }
            })
            f.cast(60)
            _ = f.heal(80)
            f.keys.now += 0.95
            _ = f.heal(60)
            f.keys.now += 0.05
            let atCooldown = f.heal(60)
            f.keys.now += 0.05
            let afterDelay = f.heal(60)
            XCTAssertEqual([atCooldown, afterDelay], [nil, "normal"])
        }
    }
}
