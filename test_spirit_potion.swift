#!/usr/bin/env swift

import Foundation

// Human-like random (same as production)
func testHumanRandom(median: Double, spread: Double = 0.3) -> Double {
    let u1 = Double.random(in: 0.0001...0.9999)
    let u2 = Double.random(in: 0.0001...0.9999)
    let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    let value = exp(log(median) + spread * z)
    return Swift.max(median * 0.5, Swift.min(median * 3.0, value))
}

func testHumanRandom(median: Double, spread: Double = 0.3, min minVal: Double, max maxVal: Double) -> Double {
    let value = testHumanRandom(median: median, spread: spread)
    return Swift.max(minVal, Swift.min(maxVal, value))
}

// Mock KeyPress Service
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
    var f3Count: Int { pressedKeys.filter { $0 == "F3" }.count }
    var f4Count: Int { pressedKeys.filter { $0 == "F4" }.count }
}

struct HealConfig {
    var enabled: Bool
    var threshold: Int
    var hotkey: String
}

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
    var spiritPotionHeal: Bool = false
    var spiritPotionHotkey: String = "F3"
    var spiritPotionThreshold: Int = 40
    
    private var lastSpellCastTime: Date = .distantPast
    private var lastPotionCastTime: Date = .distantPast
    
    private var currentSpellCooldownTarget: TimeInterval = 0.5
    private var currentPotionCooldownTarget: TimeInterval = 0.5
    
    init(keyPress: MockKeyPressService) {
        self.keyPress = keyPress
    }
    
    var isSpellOnCooldown: Bool {
        Date().timeIntervalSince(lastSpellCastTime) < currentSpellCooldownTarget
    }
    
    var isPotionOnCooldown: Bool {
        Date().timeIntervalSince(lastPotionCastTime) < currentPotionCooldownTarget
    }
    
    func resetSpellCooldown() {
        lastSpellCastTime = .distantPast
    }
    
    func resetPotionCooldown() {
        lastPotionCastTime = .distantPast
    }
    
    func resetAllCooldowns() {
        resetSpellCooldown()
        resetPotionCooldown()
    }
    
    func getHPPercent(_ currentHP: Int) -> Double {
        guard let max = maxHP, max > 0 else { return 100.0 }
        return (Double(currentHP) / Double(max)) * 100.0
    }
    
    private func randomSpellCooldown() -> TimeInterval {
        testHumanRandom(median: spellCooldown + 0.08, spread: 0.3, min: spellCooldown, max: spellCooldown + 0.4)
    }

    private func randomPotionCooldown() -> TimeInterval {
        testHumanRandom(median: potionCooldown + 0.06, spread: 0.3, min: potionCooldown, max: potionCooldown + 0.35)
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
    
    func checkSpiritPotionHeal(currentHP: Int, currentMana: Int) -> (spellCast: Bool, potionUsed: Bool) {
        guard maxHP != nil else { return (false, false) }

        let hpPercent = getHPPercent(currentHP)
        let needsCriticalHeal = criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold)
        let needsSpiritPotion = hpPercent < Double(spiritPotionThreshold)

        guard needsCriticalHeal || needsSpiritPotion else { return (false, false) }

        var spellCast = false
        var potionUsed = false

        if needsCriticalHeal && !isSpellOnCooldown {
            castSpell(criticalHeal)
            spellCast = true
        }

        if needsSpiritPotion && !isPotionOnCooldown {
            usePotion(spiritPotionHotkey)
            potionUsed = true
        }

        return (spellCast, potionUsed)
    }
    
    func checkNormalHealOnly(currentHP: Int) -> Bool {
        guard maxHP != nil else { return false }
        guard !isSpellOnCooldown else { return false }
        
        let hpPercent = getHPPercent(currentHP)
        
        if heal.enabled && hpPercent < Double(heal.threshold) {
            castSpell(heal)
            return true
        }
        
        return false
    }
}

// Test Runner
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
    print("RUNNING SPIRIT POTION HEAL TESTS")
    print(String(repeating: "=", count: 60) + "\n")
    
    let keyPress = MockKeyPressService()
    let healer = TestAutoHealer(keyPress: keyPress)
    healer.maxHP = 1000
    healer.maxMana = 2000
    
    // TEST 1: Both thresholds breached - triggers both spell and potion
    print("\n--- TEST 1: Both thresholds breached - triggers both ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.spiritPotionHeal = true
    healer.criticalHeal.threshold = 50
    healer.spiritPotionThreshold = 40

    let result1 = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)

    test("HP=30% triggers both (crit=50%, spirit=40%)", result1.spellCast && result1.potionUsed)
    test("F2 (Critical Heal) pressed", keyPress.f2Count == 1)
    test("F3 (Spirit Potion) pressed", keyPress.f3Count == 1)
    test("Both keys pressed", keyPress.pressedKeys == ["F2", "F3"])

    // TEST 2: Above both thresholds - no action
    print("\n--- TEST 2: Above both thresholds - no action ---")
    keyPress.reset()
    healer.resetAllCooldowns()

    let result2 = healer.checkSpiritPotionHeal(currentHP: 600, currentMana: 1500)

    test("HP=60% (above both) - no action", !result2.spellCast && !result2.potionUsed)
    test("No keys pressed", keyPress.pressedKeys.isEmpty)
    
    // TEST 3: Spell cooldown blocks only spell
    print("\n--- TEST 3: Spell cooldown blocks only spell ---")
    keyPress.reset()
    healer.resetAllCooldowns()

    _ = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)
    keyPress.reset()
    healer.resetPotionCooldown()

    let result3 = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)

    test("Spell on cooldown, only potion used", !result3.spellCast && result3.potionUsed)
    test("Only F3 pressed", keyPress.pressedKeys == ["F3"])

    // TEST 4: Potion cooldown blocks only potion
    print("\n--- TEST 4: Potion cooldown blocks only potion ---")
    keyPress.reset()
    healer.resetAllCooldowns()

    _ = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)
    keyPress.reset()
    healer.resetSpellCooldown()

    let result4 = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)

    test("Potion on cooldown, only spell cast", result4.spellCast && !result4.potionUsed)
    test("Only F2 pressed", keyPress.pressedKeys == ["F2"])
    
    // TEST 5: Normal heal works independently
    print("\n--- TEST 5: Normal heal works independently ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.heal.threshold = 75
    
    let normalResult = healer.checkNormalHealOnly(currentHP: 700)
    
    test("HP=70% triggers normal heal", normalResult)
    test("F1 pressed", keyPress.f1Count == 1)
    
    // TEST 6: Custom Spirit Potion hotkey
    print("\n--- TEST 6: Custom Spirit Potion hotkey ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalHeal.threshold = 50
    healer.spiritPotionThreshold = 40
    healer.spiritPotionHotkey = "F5"

    _ = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)

    test("Custom hotkey F5 pressed", keyPress.pressedKeys.contains("F5"))
    test("F3 NOT pressed", !keyPress.pressedKeys.contains("F3"))

    healer.spiritPotionHotkey = "F3"
    
    // TEST 7: Critical disabled - spirit potion still fires at its own threshold
    print("\n--- TEST 7: Critical disabled - spirit potion still fires ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalHeal.enabled = false

    let result7 = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)

    test("Critical disabled - spirit potion still fires", !result7.spellCast && result7.potionUsed)
    test("Only F3 pressed", keyPress.pressedKeys == ["F3"])

    healer.criticalHeal.enabled = true

    // TEST 8: Both cooldowns block everything
    print("\n--- TEST 8: Both cooldowns active - nothing happens ---")
    keyPress.reset()
    healer.resetAllCooldowns()

    _ = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)
    keyPress.reset()
    let result8 = healer.checkSpiritPotionHeal(currentHP: 300, currentMana: 1500)

    test("Both cooldowns active - no keys pressed", keyPress.pressedKeys.isEmpty)
    test("Nothing cast/used", !result8.spellCast && !result8.potionUsed)

    // TEST 9: HP between thresholds - only critical heal fires, not spirit potion
    print("\n--- TEST 9: HP between thresholds - only critical heal ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalHeal.threshold = 50
    healer.spiritPotionThreshold = 30

    let result9 = healer.checkSpiritPotionHeal(currentHP: 400, currentMana: 1500)

    test("HP=40% (crit=50%, spirit=30%) - only spell", result9.spellCast && !result9.potionUsed)
    test("Only F2 pressed", keyPress.pressedKeys == ["F2"])

    // TEST 10: Spirit threshold higher than critical - only spirit potion fires
    print("\n--- TEST 10: Spirit threshold higher - only spirit potion ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalHeal.threshold = 30
    healer.spiritPotionThreshold = 50

    let result10 = healer.checkSpiritPotionHeal(currentHP: 400, currentMana: 1500)

    test("HP=40% (crit=30%, spirit=50%) - only potion", !result10.spellCast && result10.potionUsed)
    test("Only F3 pressed", keyPress.pressedKeys == ["F3"])
    
    // SUMMARY
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

runTests()
