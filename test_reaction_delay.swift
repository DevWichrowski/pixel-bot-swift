#!/usr/bin/env swift

import Foundation

// ============================================
// REACTION DELAY TESTS
// Tests for human-like reaction time simulation:
// 1. First heal after HP drop is delayed 100-300ms
// 2. Subsequent heals (while still fighting) have no extra delay
// 3. Reaction resets when HP returns above threshold
// ============================================

// ============================================
// MOCK CLASSES FOR TESTING
// ============================================

class MockKeyPressService {
    var pressedKeys: [String] = []

    func pressKey(_ key: String) {
        pressedKeys.append(key)
        print("  ⌨️ PRESSED: \(key)")
    }

    func reset() {
        pressedKeys = []
    }

    var lastKey: String? { pressedKeys.last }
    var f1Count: Int { pressedKeys.filter { $0 == "F1" }.count }
    var f2Count: Int { pressedKeys.filter { $0 == "F2" }.count }
    var f4Count: Int { pressedKeys.filter { $0 == "F4" }.count }
}

struct HealConfig {
    var enabled: Bool
    var threshold: Int
    var hotkey: String
}

// ============================================
// AUTO HEALER WITH REACTION DELAY
// ============================================

class TestAutoHealer {
    private let keyPress: MockKeyPressService

    var spellCooldown: TimeInterval = 0.5
    var potionCooldown: TimeInterval = 0.5

    var maxHP: Int?
    var maxMana: Int?

    var heal = HealConfig(enabled: true, threshold: 75, hotkey: "F1")
    var criticalHeal = HealConfig(enabled: true, threshold: 50, hotkey: "F2")
    var manaRestore = HealConfig(enabled: true, threshold: 60, hotkey: "F4")

    var criticalIsPotion: Bool = false

    private var lastSpellCastTime: Date = .distantPast
    private var lastPotionCastTime: Date = .distantPast

    private var currentSpellCooldownTarget: TimeInterval = 0.5
    private var currentPotionCooldownTarget: TimeInterval = 0.5

    // Reaction delay state
    private var isReacting: Bool = false
    private var reactionEndTime: Date = .distantPast
    var wasHPBelowThreshold: Bool = false

    // Expose for testing
    var lastReactionDelay: TimeInterval = 0

    init(keyPress: MockKeyPressService) {
        self.keyPress = keyPress
    }

    private func randomSpellCooldown() -> TimeInterval {
        let maxOffset = Double.random(in: 0.1...0.3)
        return Double.random(in: spellCooldown...(spellCooldown + maxOffset))
    }

    private func randomPotionCooldown() -> TimeInterval {
        let maxOffset = Double.random(in: 0.08...0.25)
        return Double.random(in: potionCooldown...(potionCooldown + maxOffset))
    }

    private func randomReactionDelay() -> TimeInterval {
        Double.random(in: 0.1...0.3)
    }

    /// Check if reaction delay is needed before healing.
    /// Returns true if healing is allowed (no delay or delay has passed).
    func checkReactionDelay(hpBelowThreshold: Bool) -> Bool {
        if !hpBelowThreshold {
            wasHPBelowThreshold = false
            isReacting = false
            return true
        }

        if wasHPBelowThreshold {
            return true
        }

        if !isReacting {
            isReacting = true
            let delay = randomReactionDelay()
            lastReactionDelay = delay
            reactionEndTime = Date().addingTimeInterval(delay)
            return false
        }

        if Date() < reactionEndTime {
            return false
        }

        wasHPBelowThreshold = true
        isReacting = false
        return true
    }

    var isSpellOnCooldown: Bool {
        Date().timeIntervalSince(lastSpellCastTime) < currentSpellCooldownTarget
    }

    var isPotionOnCooldown: Bool {
        Date().timeIntervalSince(lastPotionCastTime) < currentPotionCooldownTarget
    }

    func resetAllCooldowns() {
        lastSpellCastTime = .distantPast
        lastPotionCastTime = .distantPast
    }

    func resetReactionState() {
        isReacting = false
        wasHPBelowThreshold = false
        reactionEndTime = .distantPast
    }

    func getHPPercent(_ currentHP: Int) -> Double {
        guard let max = maxHP, max > 0 else { return 100.0 }
        return (Double(currentHP) / Double(max)) * 100.0
    }

    func getManaPercent(_ currentMana: Int) -> Double {
        guard let max = maxMana, max > 0 else { return 100.0 }
        return (Double(currentMana) / Double(max)) * 100.0
    }

    private func castSpell(_ config: HealConfig) {
        keyPress.pressKey(config.hotkey)
        lastSpellCastTime = Date()
        currentSpellCooldownTarget = randomSpellCooldown()
    }

    private func usePotion(_ hotkey: String) {
        keyPress.pressKey(hotkey)
        lastPotionCastTime = Date()
        currentPotionCooldownTarget = randomPotionCooldown()
    }

    @discardableResult
    func checkAndHeal(currentHP: Int) -> String? {
        guard maxHP != nil else { return nil }

        let hpPercent = getHPPercent(currentHP)
        let needsHeal = (heal.enabled && hpPercent < Double(heal.threshold)) ||
                        (criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold))

        guard checkReactionDelay(hpBelowThreshold: needsHeal) else { return nil }
        guard !isSpellOnCooldown else { return nil }

        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            castSpell(criticalHeal)
            return "critical"
        }

        if heal.enabled && hpPercent < Double(heal.threshold) {
            castSpell(heal)
            return "normal"
        }

        return nil
    }

    @discardableResult
    func checkNormalHealOnly(currentHP: Int) -> Bool {
        guard maxHP != nil else { return false }

        let hpPercent = getHPPercent(currentHP)
        let needsHeal = heal.enabled && hpPercent < Double(heal.threshold)

        if !wasHPBelowThreshold {
            guard checkReactionDelay(hpBelowThreshold: needsHeal) else { return false }
        }

        guard !isSpellOnCooldown else { return false }

        if needsHeal {
            castSpell(heal)
            return true
        }

        return false
    }

    func checkCriticalAndManaWithPriority(currentHP: Int, currentMana: Int) -> (healType: String?, manaRestored: Bool) {
        let hpPercent = maxHP != nil ? getHPPercent(currentHP) : 100.0
        let manaPercent = maxMana != nil ? getManaPercent(currentMana) : 100.0
        let needsHeal = criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold)

        guard checkReactionDelay(hpBelowThreshold: needsHeal) else { return (nil, false) }
        guard !isPotionOnCooldown else { return (nil, false) }

        if needsHeal {
            usePotion(criticalHeal.hotkey)
            return ("critical", false)
        }

        if manaRestore.enabled && manaPercent < Double(manaRestore.threshold) {
            usePotion(manaRestore.hotkey)
            return (nil, true)
        }

        return (nil, false)
    }
}

// ============================================
// TEST RUNNER
// ============================================

var passedTests = 0
var failedTests = 0

func test(_ name: String, _ condition: Bool) {
    if condition {
        print("✅ PASS: \(name)")
        passedTests += 1
    } else {
        print("❌ FAIL: \(name)")
        failedTests += 1
    }
}

func runTests() {
    print("\n" + String(repeating: "=", count: 60))
    print("RUNNING REACTION DELAY TESTS")
    print(String(repeating: "=", count: 60) + "\n")

    let keyPress = MockKeyPressService()
    let healer = TestAutoHealer(keyPress: keyPress)
    healer.maxHP = 1000
    healer.maxMana = 500

    // ============================================
    // TEST 1: First heal after HP drop should be blocked by reaction delay
    // ============================================
    print("\n--- TEST 1: First heal after HP drop is blocked (reaction delay) ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.resetReactionState()

    // HP drops to 60% — first check should NOT heal (reaction delay starts)
    let result1 = healer.checkAndHeal(currentHP: 600)

    test("should not heal immediately on first HP drop", result1 == nil)
    test("should not press any key", keyPress.pressedKeys.isEmpty)

    // ============================================
    // TEST 2: After reaction delay passes, heal should fire
    // ============================================
    print("\n--- TEST 2: Heal fires after reaction delay passes ---")
    keyPress.reset()

    // Wait for reaction delay to pass (max 300ms + margin)
    Thread.sleep(forTimeInterval: 0.35)

    let result2 = healer.checkAndHeal(currentHP: 600)

    test("should heal after reaction delay", result2 == "normal")
    test("should press F1", keyPress.lastKey == "F1")

    // ============================================
    // TEST 3: Subsequent heals have no extra reaction delay
    // ============================================
    print("\n--- TEST 3: Subsequent heals have no reaction delay ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    // DON'T reset reaction state — we're still "fighting"

    let result3 = healer.checkAndHeal(currentHP: 600)

    test("should heal immediately (already reacting)", result3 == "normal")
    test("should press F1", keyPress.lastKey == "F1")

    // ============================================
    // TEST 4: HP returns to normal, then drops again — new reaction delay
    // ============================================
    print("\n--- TEST 4: HP recovers then drops — new reaction delay ---")
    keyPress.reset()
    healer.resetAllCooldowns()

    // HP is fine — this resets reaction state
    _ = healer.checkAndHeal(currentHP: 900)

    test("should not heal at 90% HP", keyPress.pressedKeys.isEmpty)

    // HP drops again — should trigger new reaction delay
    let result4 = healer.checkAndHeal(currentHP: 600)

    test("should NOT heal immediately (new reaction delay)", result4 == nil)
    test("should not press any key", keyPress.pressedKeys.isEmpty)

    // Wait and heal
    Thread.sleep(forTimeInterval: 0.35)

    let result4b = healer.checkAndHeal(currentHP: 600)
    test("should heal after new reaction delay", result4b == "normal")

    // ============================================
    // TEST 5: Reaction delay is in correct range (100-300ms)
    // ============================================
    print("\n--- TEST 5: Reaction delay values in range 0.1-0.3s ---")

    var delays: [TimeInterval] = []
    for _ in 1...50 {
        healer.resetReactionState()
        healer.resetAllCooldowns()
        _ = healer.checkAndHeal(currentHP: 600) // triggers reaction
        delays.append(healer.lastReactionDelay)
    }

    let minDelay = delays.min() ?? 0
    let maxDelay = delays.max() ?? 0

    print("  Reaction delays: min=\(String(format: "%.3f", minDelay))s, max=\(String(format: "%.3f", maxDelay))s")

    test("All delays >= 0.1s", delays.allSatisfy { $0 >= 0.1 })
    test("All delays <= 0.3s", delays.allSatisfy { $0 <= 0.3 })
    test("Delays have variation", Set(delays.map { Int($0 * 100) }).count > 1)

    // ============================================
    // TEST 6: Critical heal also has reaction delay
    // ============================================
    print("\n--- TEST 6: Critical heal also gets reaction delay ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.resetReactionState()

    // HP at 30% — critical territory
    let result6 = healer.checkAndHeal(currentHP: 300)

    test("should not critical heal immediately", result6 == nil)
    test("should not press F2", keyPress.pressedKeys.isEmpty)

    Thread.sleep(forTimeInterval: 0.35)

    let result6b = healer.checkAndHeal(currentHP: 300)
    test("should critical heal after delay", result6b == "critical")
    test("should press F2", keyPress.lastKey == "F2")

    // ============================================
    // TEST 7: checkNormalHealOnly also respects reaction delay
    // ============================================
    print("\n--- TEST 7: checkNormalHealOnly respects reaction delay ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.resetReactionState()

    let result7 = healer.checkNormalHealOnly(currentHP: 600)

    test("should not heal immediately (normal only mode)", result7 == false)
    test("should not press any key", keyPress.pressedKeys.isEmpty)

    Thread.sleep(forTimeInterval: 0.35)

    let result7b = healer.checkNormalHealOnly(currentHP: 600)
    test("should heal after delay (normal only mode)", result7b == true)
    test("should press F1", keyPress.lastKey == "F1")

    // ============================================
    // TEST 8: checkCriticalAndManaWithPriority respects reaction delay
    // ============================================
    print("\n--- TEST 8: criticalIsPotion mode respects reaction delay ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.resetReactionState()

    let result8 = healer.checkCriticalAndManaWithPriority(currentHP: 300, currentMana: 500)

    test("should not critical-potion heal immediately", result8.healType == nil)

    Thread.sleep(forTimeInterval: 0.35)

    let result8b = healer.checkCriticalAndManaWithPriority(currentHP: 300, currentMana: 500)
    test("should critical-potion heal after delay", result8b.healType == "critical")

    // ============================================
    // TEST 9: Mana restore has NO reaction delay (not HP-based)
    // ============================================
    print("\n--- TEST 9: Mana restore not blocked by reaction delay ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.resetReactionState()

    // HP is fine, mana is low — reaction delay should not block mana restore
    let result9 = healer.checkCriticalAndManaWithPriority(currentHP: 900, currentMana: 200)

    test("should restore mana without reaction delay", result9.manaRestored == true)
    test("should press F4", keyPress.lastKey == "F4")

    // ============================================
    // TEST 10: Rapid HP changes — reaction delay only on initial drop
    // ============================================
    print("\n--- TEST 10: Rapid HP fluctuations ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.resetReactionState()

    // First drop — blocked
    _ = healer.checkAndHeal(currentHP: 600)
    test("should block first drop", keyPress.pressedKeys.isEmpty)

    // Wait for delay
    Thread.sleep(forTimeInterval: 0.35)

    // Heal fires
    _ = healer.checkAndHeal(currentHP: 600)
    test("should heal after delay", keyPress.f1Count == 1)

    // HP still low, more heals — should be immediate (no new delay)
    healer.resetAllCooldowns()
    _ = healer.checkAndHeal(currentHP: 650)
    test("should heal immediately while still fighting", keyPress.f1Count == 2)

    healer.resetAllCooldowns()
    _ = healer.checkAndHeal(currentHP: 550)
    test("should still heal immediately", keyPress.f1Count == 3)

    // ============================================
    // SUMMARY
    // ============================================
    print("\n" + String(repeating: "=", count: 60))
    print("TEST RESULTS: \(passedTests) passed, \(failedTests) failed")
    print(String(repeating: "=", count: 60) + "\n")

    if failedTests > 0 {
        print("❌ SOME TESTS FAILED!")
        exit(1)
    } else {
        print("✅ ALL TESTS PASSED!")
        exit(0)
    }
}

// Run the tests
runTests()
