#!/usr/bin/env swift

import Foundation

private var passed = 0
private var failed = 0

private func test(_ description: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("✅ \(description)")
        passed += 1
    } else {
        print("❌ \(description)")
        failed += 1
    }
}

final class TestHealer {
    static let healingGroupCooldown: TimeInterval = 1.0

    private var pendingReading: (current: Int, maximum: Int)?
    private var pendingCount = 0
    private var confirmedReading: (current: Int, maximum: Int)?
    private var lastKeyDown: TimeInterval?

    var keyDownCount = 0
    var now: TimeInterval = 100

    @discardableResult
    func observe(current: Int, maximum: Int) -> Bool {
        let reading = (current: current, maximum: maximum)
        if confirmedReading?.current != reading.current ||
            confirmedReading?.maximum != reading.maximum {
            if pendingReading?.current == reading.current &&
                pendingReading?.maximum == reading.maximum {
                pendingCount += 1
            } else {
                pendingReading = reading
                pendingCount = 1
            }
            guard pendingCount >= 2 else { return false }
            confirmedReading = reading
            pendingReading = nil
            pendingCount = 0
        }

        guard Double(current) / Double(maximum) < 0.75 else { return false }
        if let lastKeyDown,
           now - lastKeyDown < Self.healingGroupCooldown {
            return false
        }

        lastKeyDown = now
        keyDownCount += 1
        return true
    }
}

print("\n=== TWO-READ HP AND HEALING COOLDOWN TESTS ===\n")

let healer = TestHealer()
let firstResult = healer.observe(current: 60, maximum: 100)
test("should not heal after only one valid fast HP reading", firstResult == false)

let confirmationStarted = ProcessInfo.processInfo.systemUptime
let secondResult = healer.observe(current: 60, maximum: 100)
let confirmationLatency = ProcessInfo.processInfo.systemUptime - confirmationStarted
test(
    "should heal immediately when the second matching HP reading confirms the value",
    secondResult && confirmationLatency < 0.01
)

healer.now += 0.999
let beforeCooldown = healer.observe(current: 60, maximum: 100)
healer.now += 0.001
let atCooldown = healer.observe(current: 60, maximum: 100)
test(
    "should use a fixed one second cooldown measured from keyDown",
    !beforeCooldown && atCooldown && healer.keyDownCount == 2
)

print("\n=== RESULTS ===")
print("Passed: \(passed)")
print("Failed: \(failed)")

if failed == 0 {
    print("\n🎉 ALL TESTS PASSED")
} else {
    print("\n⚠️ SOME TESTS FAILED")
    exit(1)
}
