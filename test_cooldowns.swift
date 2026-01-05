#!/usr/bin/env swift

import Foundation

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

// ============================================
// HEAL CONFIG (same as in app)
// ============================================

struct HealConfig {
    var enabled: Bool
    var threshold: Int
    var hotkey: String
}

// ============================================
// AUTO HEALER WITH SEPARATE COOLDOWNS
// ============================================

class TestAutoHealer {
    private let keyPress: MockKeyPressService
    
    // Configurable cooldowns
    var spellCooldown: TimeInterval = 0.5   // For heal spells
    var potionCooldown: TimeInterval = 0.5  // For potions
    
    var maxHP: Int?
    var maxMana: Int?
    
    var heal = HealConfig(enabled: true, threshold: 75, hotkey: "F1")
    var criticalHeal = HealConfig(enabled: true, threshold: 50, hotkey: "F2")
    var manaRestore = HealConfig(enabled: true, threshold: 60, hotkey: "F4")
    
    var criticalIsPotion: Bool = false
    
    // Separate cooldown tracking
    private var lastSpellCastTime: Date = .distantPast
    private var lastPotionCastTime: Date = .distantPast
    
    init(keyPress: MockKeyPressService) {
        self.keyPress = keyPress
    }
    
    var isSpellOnCooldown: Bool {
        Date().timeIntervalSince(lastSpellCastTime) < spellCooldown
    }
    
    var isPotionOnCooldown: Bool {
        Date().timeIntervalSince(lastPotionCastTime) < potionCooldown
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
    
    func getManaPercent(_ currentMana: Int) -> Double {
        guard let max = maxMana, max > 0 else { return 100.0 }
        return (Double(currentMana) / Double(max)) * 100.0
    }
    
    // Cast spell (uses spell cooldown)
    private func castSpell(_ config: HealConfig) {
        keyPress.pressKey(config.hotkey)
        lastSpellCastTime = Date()
    }
    
    // Use potion (uses potion cooldown)
    private func usePotion(_ hotkey: String) {
        keyPress.pressKey(hotkey)
        lastPotionCastTime = Date()
    }
    
    // MARK: - checkAndHeal (standard mode - criticalIsPotion = false)
    // Both normal and critical heal use spell cooldown
    
    @discardableResult
    func checkAndHeal(currentHP: Int) -> String? {
        guard maxHP != nil else { return nil }
        guard !isSpellOnCooldown else { return nil }
        
        let hpPercent = getHPPercent(currentHP)
        
        // Critical heal has priority
        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            castSpell(criticalHeal)
            return "critical"
        }
        
        // Normal heal
        if heal.enabled && hpPercent < Double(heal.threshold) {
            castSpell(heal)
            return "normal"
        }
        
        return nil
    }
    
    // MARK: - checkNormalHealOnly (criticalIsPotion mode)
    // Uses spell cooldown
    
    @discardableResult
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
    
    // MARK: - checkAndRestoreMana (uses potion cooldown)
    
    @discardableResult
    func checkAndRestoreMana(currentMana: Int) -> Bool {
        guard maxMana != nil else { return false }
        guard !isPotionOnCooldown else { return false }
        
        let manaPercent = getManaPercent(currentMana)
        
        if manaRestore.enabled && manaPercent < Double(manaRestore.threshold) {
            usePotion(manaRestore.hotkey)
            return true
        }
        
        return false
    }
    
    // MARK: - checkCriticalAndManaWithPriority (criticalIsPotion mode)
    // Both critical and mana use potion cooldown
    
    func checkCriticalAndManaWithPriority(currentHP: Int, currentMana: Int) -> (healType: String?, manaRestored: Bool) {
        guard !isPotionOnCooldown else { return (nil, false) }
        
        let hpPercent = maxHP != nil ? getHPPercent(currentHP) : 100.0
        let manaPercent = maxMana != nil ? getManaPercent(currentMana) : 100.0
        
        // Priority 1: Critical heal (life-saving) - uses potion
        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            usePotion(criticalHeal.hotkey)
            return ("critical", false)
        }
        
        // Priority 2: Mana restore - uses potion
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
    print("RUNNING COOLDOWN SYSTEM TESTS")
    print(String(repeating: "=", count: 60) + "\n")
    
    let keyPress = MockKeyPressService()
    let healer = TestAutoHealer(keyPress: keyPress)
    healer.maxHP = 1000
    healer.maxMana = 500
    
    // ============================================
    // TEST 1: Spell cooldown is independent from potion cooldown
    // ============================================
    print("\n--- TEST 1: Spell and potion cooldowns are independent ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    
    // Cast a spell
    _ = healer.checkAndHeal(currentHP: 600)  // HP 60% - normal heal
    
    test("Normal heal should use F1", keyPress.lastKey == "F1")
    test("Spell cooldown should be active", healer.isSpellOnCooldown)
    test("Potion cooldown should NOT be active", !healer.isPotionOnCooldown)
    
    // Mana should still work (different cooldown)
    _ = healer.checkAndRestoreMana(currentMana: 200)  // Mana 40%
    
    test("Mana restore should work while spell on cooldown", keyPress.lastKey == "F4")
    test("Potion cooldown should now be active", healer.isPotionOnCooldown)
    
    // ============================================
    // TEST 2: Standard mode - heals share spell cooldown
    // ============================================
    print("\n--- TEST 2: Standard mode - heals share spell cooldown ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalIsPotion = false
    
    // Cast critical heal
    _ = healer.checkAndHeal(currentHP: 400)  // HP 40% - critical heal
    
    test("Critical heal (standard mode) triggers F2", keyPress.lastKey == "F2")
    test("Spell cooldown is active after critical heal", healer.isSpellOnCooldown)
    
    // Try normal heal immediately - should be blocked
    let result = healer.checkAndHeal(currentHP: 600)  // HP 60%
    
    test("Normal heal blocked by spell cooldown", result == nil)
    test("Only one key press total", keyPress.pressedKeys.count == 1)
    
    // ============================================
    // TEST 3: Potion mode - critical and mana share potion cooldown
    // ============================================
    print("\n--- TEST 3: Potion mode - critical and mana share potion cooldown ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalIsPotion = true
    
    // Cast critical heal (as potion)
    _ = healer.checkCriticalAndManaWithPriority(currentHP: 400, currentMana: 200)
    
    test("Critical (potion mode) triggers F2", keyPress.lastKey == "F2")
    test("Potion cooldown is active", healer.isPotionOnCooldown)
    test("Spell cooldown is NOT active", !healer.isSpellOnCooldown)
    
    // Mana should be blocked (same potion cooldown)
    let manaResult = healer.checkAndRestoreMana(currentMana: 200)
    
    test("Mana blocked by potion cooldown", manaResult == false)
    test("Only one key press total", keyPress.pressedKeys.count == 1)
    
    // ============================================
    // TEST 4: Potion mode - normal heal uses spell cooldown
    // ============================================
    print("\n--- TEST 4: Potion mode - normal heal independent ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalIsPotion = true
    
    // Use mana potion first
    _ = healer.checkAndRestoreMana(currentMana: 200)
    
    test("Mana restore presses F4", keyPress.lastKey == "F4")
    test("Potion cooldown is active", healer.isPotionOnCooldown)
    
    // Normal heal should still work (uses spell cooldown)
    _ = healer.checkNormalHealOnly(currentHP: 600)
    
    test("Normal heal works while potion on cooldown", keyPress.lastKey == "F1")
    test("Both F4 and F1 were pressed", keyPress.f4Count == 1 && keyPress.f1Count == 1)
    
    // ============================================
    // TEST 5: Configurable cooldown values
    // ============================================
    print("\n--- TEST 5: Configurable cooldown values ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    
    // Set different cooldowns
    healer.spellCooldown = 0.1  // 100ms
    healer.potionCooldown = 0.2  // 200ms
    
    // Cast spell and wait
    _ = healer.checkAndHeal(currentHP: 600)
    test("First heal works", keyPress.f1Count == 1)
    
    // Wait 150ms - spell CD should expire, potion still active
    usleep(150_000)
    
    _ = healer.checkAndHeal(currentHP: 600)
    test("Spell works after spell cooldown expires", keyPress.f1Count == 2)
    
    // Reset cooldowns to default for remaining tests
    healer.spellCooldown = 0.5
    healer.potionCooldown = 0.5
    
    // ============================================
    // TEST 6: Standard mode - mana uses potion cooldown
    // ============================================
    print("\n--- TEST 6: Standard mode - mana independent from heals ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalIsPotion = false
    
    // Cast heal
    _ = healer.checkAndHeal(currentHP: 600)
    test("Normal heal works", keyPress.f1Count == 1)
    
    // Mana should work (different cooldown)
    _ = healer.checkAndRestoreMana(currentMana: 200)
    test("Mana works while spell on cooldown", keyPress.f4Count == 1)
    
    // ============================================
    // TEST 7: Full potion mode cycle
    // ============================================
    print("\n--- TEST 7: Full potion mode cycle ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalIsPotion = true
    healer.spellCooldown = 0.05
    healer.potionCooldown = 0.05
    
    // Simulate multiple cycles
    for i in 1...5 {
        healer.resetAllCooldowns()
        
        // Check potions first (critical + mana)
        _ = healer.checkCriticalAndManaWithPriority(currentHP: 800, currentMana: 200)  // Mana low
        
        usleep(60_000)  // Wait for cooldowns
        
        // Check spell (normal heal)
        _ = healer.checkNormalHealOnly(currentHP: 600)
        
        usleep(60_000)
    }
    
    test("5 mana restores triggered", keyPress.f4Count == 5)
    test("5 normal heals triggered", keyPress.f1Count == 5)
    test("0 critical heals (HP was > 50%)", keyPress.f2Count == 0)
    
    // Reset
    healer.spellCooldown = 0.5
    healer.potionCooldown = 0.5
    
    // ============================================
    // TEST 8: Critical priority in potion mode
    // ============================================
    print("\n--- TEST 8: Critical > Mana priority in potion mode ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.criticalIsPotion = true
    
    // Both HP and Mana low
    let (healType, manaRestored) = healer.checkCriticalAndManaWithPriority(currentHP: 400, currentMana: 200)
    
    test("Critical heal has priority", healType == "critical")
    test("Mana was NOT restored", manaRestored == false)
    test("F2 was pressed (critical)", keyPress.lastKey == "F2")
    test("F4 was NOT pressed", keyPress.f4Count == 0)
    
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
