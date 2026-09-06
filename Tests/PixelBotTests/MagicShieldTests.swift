import XCTest
@testable import PixelBot

final class MagicShieldTests: XCTestCase {
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
        var requests: [Request] = []
        var submitted = 0
        var accepts = true

        func pressKey(_ key: String, priority: KeyPressPriority, group: KeyPressRequestGroup?,
                      validUntil: TimeInterval?, lifecycle: KeyPressLifecycleHandler?) -> Bool {
            pressKey(key, priority: priority, group: group, validUntil: validUntil,
                     isValid: { true }, lifecycle: lifecycle)
        }

        func pressKey(_ key: String, priority: KeyPressPriority, group: KeyPressRequestGroup?,
                      validUntil: TimeInterval?, isValid: @escaping () -> Bool,
                      lifecycle: KeyPressLifecycleHandler?) -> Bool {
            guard accepts else { return false }
            submitted += 1
            requests.append(Request(key: key, priority: priority, group: group,
                                    validUntil: validUntil, isValid: isValid, lifecycle: lifecycle))
            return true
        }

        func cancelPendingRequests(in group: KeyPressRequestGroup) {
            let cancelled = requests.filter { $0.group == group }
            requests.removeAll { $0.group == group }
            cancelled.forEach { emit($0, .cancelled, at: ProcessInfo.processInfo.systemUptime) }
        }

        func finish(_ phase: KeyPressLifecyclePhase, at uptime: TimeInterval) {
            guard !requests.isEmpty else { return }
            let request = requests.removeFirst()
            let actualPhase: KeyPressLifecyclePhase
            if phase == .keyDown && (!request.isValid() || (request.validUntil.map { uptime >= $0 } ?? false)) {
                actualPhase = .cancelled
            } else {
                actualPhase = phase
            }
            emit(request, actualPhase, at: uptime)
        }

        private func emit(_ request: Request, _ phase: KeyPressLifecyclePhase, at uptime: TimeInterval) {
            request.lifecycle?(KeyPressLifecycleEvent(requestID: request.id, key: request.key,
                priority: request.priority, phase: phase, timestamp: uptime, queueWait: 0,
                validityRemaining: request.validUntil.map { $0 - uptime }))
        }
    }

    private final class Fixture {
        let keys = PendingKeys()
        let support = SupportCooldown()
        let feature: AutoMagicShield
        let start = Date(timeIntervalSince1970: 1_000)
        let uptime = ProcessInfo.processInfo.systemUptime - 100

        init() {
            feature = AutoMagicShield(keyPress: keys, support: support)
            feature.enabled = true
        }

        func frame(_ offset: Double, hp: Int = 20, mana: Int = 100,
                   shield: ShieldState = .inactive, observationAge: Double = 0) {
            let now = start.addingTimeInterval(offset)
            let captured = now.addingTimeInterval(-observationAge)
            feature.evaluate(
                hp: NumericReadout(current: hp, maximum: 100, confidence: 1,
                                   timestamp: captured, state: .valid),
                mana: NumericReadout(current: mana, maximum: 100, confidence: 1,
                                     timestamp: captured, state: .valid),
                shield: ShieldReadout(current: shield == .active ? 100 : 0, maximum: 100,
                                      confidence: 1, timestamp: captured, state: shield),
                now: now, uptime: uptime + offset)
        }

        func confirm(hp: Int = 20, mana: Int = 100, shield: ShieldState = .inactive) {
            frame(0, hp: hp, mana: mana, shield: shield)
            frame(0.03, hp: hp, mana: mana, shield: shield)
        }
    }

    func testBelowThreshold() {
        it("should queue R with emergency priority below 25 percent") {
            let fixture = Fixture()
            fixture.confirm(hp: 24)
            XCTAssertEqual(fixture.keys.requests.map { "\($0.key):\($0.priority.rawValue)" }, ["R:emergency"])
        }
    }

    func testThresholdBoundaries() {
        for hp in [0, 25, 26, 100] {
            it("should suppress shield at HP \(hp) percent") {
                let fixture = Fixture()
                fixture.confirm(hp: hp)
                XCTAssertTrue(fixture.keys.requests.isEmpty)
            }
        }
    }

    func testInsufficientMana() {
        it("should suppress shield below 50 mana") {
            let fixture = Fixture()
            fixture.confirm(mana: 49)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testExactManaMinimum() {
        it("should permit shield at exactly 50 mana") {
            let fixture = Fixture()
            fixture.confirm(mana: 50)
            XCTAssertEqual(fixture.keys.requests.count, 1)
        }
    }

    func testActiveAndUnknownShield() {
        for state in [ShieldState.active, .unknown] {
            it("should suppress shield when its state is \(state.rawValue)") {
                let fixture = Fixture()
                fixture.confirm(shield: state)
                XCTAssertTrue(fixture.keys.requests.isEmpty)
            }
        }
    }

    func testStaleReadings() {
        it("should suppress observations at the 250 millisecond expiry") {
            let fixture = Fixture()
            fixture.frame(0, observationAge: 0.25)
            fixture.frame(0.03, observationAge: 0.25)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testDuplicateFrame() {
        it("should require distinct frames to confirm inactivity") {
            let fixture = Fixture()
            fixture.frame(0)
            fixture.frame(0)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testChangingLowHP() {
        it("should confirm low HP while damage changes its numeric value") {
            let fixture = Fixture()
            fixture.frame(0, hp: 24)
            fixture.frame(0.03, hp: 19)
            XCTAssertEqual(fixture.keys.requests.count, 1)
        }
    }

    func testExpiredConfirmation() {
        it("should discard the first confirmation after a gap of 250 milliseconds") {
            let fixture = Fixture()
            fixture.frame(0)
            fixture.frame(0.25)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testPendingDuplicateSuppression() {
        it("should permit only one pending request") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.frame(0.06)
            XCTAssertEqual(fixture.keys.submitted, 1)
        }
    }

    func testRecoveryCancels() {
        it("should cancel queued shield when HP recovers before key down") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.frame(0.06, hp: 25)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testActivationCancels() {
        it("should cancel queued shield when observed capacity becomes positive") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.frame(0.06, shield: .active)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testExpiredQueuedRequest() {
        it("should expire a queued request before dispatch") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.keys.finish(.keyDown, at: fixture.uptime + 0.30)
            fixture.frame(0.31)
            fixture.frame(0.34)
            XCTAssertEqual(fixture.keys.submitted, 2)
        }
    }

    func testFailedAndCancelledAttemptsDoNotConsumeCooldown() {
        for phase in [KeyPressLifecyclePhase.failed, .cancelled] {
            it("should retain readiness after a \(phase.rawValue) dispatch") {
                let fixture = Fixture()
                fixture.confirm()
                fixture.keys.finish(phase, at: fixture.uptime + 0.04)
                fixture.frame(0.06)
                XCTAssertEqual(fixture.keys.submitted, 2)
            }
        }
    }

    func testRejectedEnqueueDoesNotConsumeCooldown() {
        it("should retry after an enqueue rejection") {
            let fixture = Fixture()
            fixture.keys.accepts = false
            fixture.confirm()
            fixture.keys.accepts = true
            fixture.frame(0.06)
            XCTAssertEqual(fixture.keys.requests.count, 1)
        }
    }

    func testCooldownStartsAtKeyDown() {
        it("should retain the 14 second attempt cooldown without activation confirmation") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.keys.finish(.keyDown, at: fixture.uptime + 0.10)
            fixture.frame(13.95)
            fixture.frame(14.03)
            XCTAssertEqual(fixture.keys.submitted, 1)
        }
    }

    func testShieldBreakReevaluation() {
        it("should retry after cooldown when shield breaks while HP stays low") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.keys.finish(.keyDown, at: fixture.uptime + 0.10)
            fixture.frame(0.12, shield: .active)
            fixture.frame(14.10)
            fixture.frame(14.13)
            XCTAssertEqual(fixture.keys.submitted, 2)
        }
    }

    func testSupportCooldownFromShield() {
        it("should block Support for two seconds after shield key down") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.keys.finish(.keyDown, at: fixture.uptime + 0.10)
            XCTAssertEqual([fixture.support.isReady(at: fixture.uptime + 2.09),
                            fixture.support.isReady(at: fixture.uptime + 2.10)], [false, true])
        }
    }

    func testDispatchedHasteRetainsSupportCooldown() {
        it("should respect a dispatched haste Support cooldown") {
            let fixture = Fixture()
            fixture.support.recordKeyDown(at: fixture.uptime)
            fixture.confirm()
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testPendingHasteYields() {
        it("should cancel pending haste when emergency shield is requested") {
            let fixture = Fixture()
            _ = fixture.keys.pressKey("X", priority: .regular, group: fixture.support.hasteGroup,
                                  validUntil: nil, lifecycle: nil)
            fixture.confirm()
            XCTAssertEqual(fixture.keys.requests.map(\.key), ["R"])
        }
    }

    func testPendingUnknownCancels() {
        it("should revoke queued shield when the latest shield reading is unknown") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.frame(0.06, shield: .unknown)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testPendingInsufficientManaCancels() {
        it("should revoke queued shield when newer mana falls below the spell cost") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.frame(0.06, mana: 49)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testPendingStaleReadingsCancel() {
        it("should revoke queued shield when necessary observations expire") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.frame(0.30, observationAge: 0.27)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testDisabledFeature() {
        it("should suppress requests while Magic Shield is disabled") {
            let fixture = Fixture()
            fixture.feature.enabled = false
            fixture.confirm()
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testShieldReadingsMustBothBeInactive() {
        it("should require two fresh inactive frames after shield becomes unknown") {
            let fixture = Fixture()
            fixture.frame(0)
            fixture.frame(0.03, shield: .unknown)
            fixture.frame(0.06)
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }

    func testStopCancellation() {
        it("should remove pending shield work on stop") {
            let fixture = Fixture()
            fixture.confirm()
            fixture.feature.cancelPendingActions()
            XCTAssertTrue(fixture.keys.requests.isEmpty)
        }
    }
}
