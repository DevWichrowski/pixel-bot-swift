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
// AUTO HEALER (simplified for testing)
// ============================================

class TestAutoHealer {
    private let keyPress: MockKeyPressService
    
    var maxHP: Int?
    var maxMana: Int?
    
    var heal = HealConfig(enabled: true, threshold: 75, hotkey: "F1")
    var criticalHeal = HealConfig(enabled: true, threshold: 50, hotkey: "F2")
    var manaRestore = HealConfig(enabled: true, threshold: 60, hotkey: "F4")
    
    var criticalIsPotion: Bool = false
    
    private var lastCastTime: Date = .distantPast
    static let COOLDOWN: TimeInterval = 1.0
    
    init(keyPress: MockKeyPressService) {
        self.keyPress = keyPress
    }
    
    var isOnCooldown: Bool {
        Date().timeIntervalSince(lastCastTime) < Self.COOLDOWN
    }
    
    func resetCooldown() {
        lastCastTime = .distantPast
    }
    
    func getHPPercent(_ currentHP: Int) -> Double {
        guard let max = maxHP, max > 0 else { return 100.0 }
        return (Double(currentHP) / Double(max)) * 100.0
    }
    
    func getManaPercent(_ currentMana: Int) -> Double {
        guard let max = maxMana, max > 0 else { return 100.0 }
        return (Double(currentMana) / Double(max)) * 100.0
    }
    
    // MARK: - checkAndHeal (used in STANDARD mode only)
    
    @discardableResult
    func checkAndHeal(currentHP: Int) -> String? {
        guard maxHP != nil else { return nil }
        guard !isOnCooldown else { return nil }
        
        let hpPercent = getHPPercent(currentHP)
        
        // Critical heal has priority
        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            keyPress.pressKey(criticalHeal.hotkey)
            lastCastTime = Date()
            return "critical"
        }
        
        // Normal heal
        if heal.enabled && hpPercent < Double(heal.threshold) {
            keyPress.pressKey(heal.hotkey)
            lastCastTime = Date()
            return "normal"
        }
        
        return nil
    }
    
    // MARK: - checkNormalHealOnly (used in criticalIsPotion mode)
    
    @discardableResult
    func checkNormalHealOnly(currentHP: Int) -> Bool {
        guard maxHP != nil else { return false }
        guard !isOnCooldown else { return false }
        
        let hpPercent = getHPPercent(currentHP)
        
        // Only normal heal - critical is handled separately
        if heal.enabled && hpPercent < Double(heal.threshold) {
            keyPress.pressKey(heal.hotkey)
            lastCastTime = Date()
            return true
        }
        
        return false
    }
    
    // MARK: - checkCriticalAndManaWithPriority (used in criticalIsPotion mode)
    
    func checkCriticalAndManaWithPriority(currentHP: Int, currentMana: Int) -> (healType: String?, manaRestored: Bool) {
        guard !isOnCooldown else { return (nil, false) }
        
        let hpPercent = maxHP != nil ? getHPPercent(currentHP) : 100.0
        let manaPercent = maxMana != nil ? getManaPercent(currentMana) : 100.0
        
        // Priority 1: Critical heal (life-saving)
        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            keyPress.pressKey(criticalHeal.hotkey)
            lastCastTime = Date()
            return ("critical", false)
        }
        
        // Priority 2: Mana restore
        if manaRestore.enabled && manaPercent < Double(manaRestore.threshold) {
            keyPress.pressKey(manaRestore.hotkey)
            lastCastTime = Date()
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
    print("RUNNING AUTO HEALER TESTS")
    print(String(repeating: "=", count: 60) + "\n")
    
    let keyPress = MockKeyPressService()
    let healer = TestAutoHealer(keyPress: keyPress)
    healer.maxHP = 1000
    healer.maxMana = 500
    
    // ============================================
    // TEST 1: checkNormalHealOnly should NEVER use critical heal
    // ============================================
    print("\n--- TEST 1: checkNormalHealOnly should NEVER use F2 (critical) ---")
    keyPress.reset()
    healer.resetCooldown()
    
    // HP at 30% (below BOTH thresholds)
    _ = healer.checkNormalHealOnly(currentHP: 300)
    
    test("checkNormalHealOnly with HP=30% should press F1", keyPress.lastKey == "F1")
    test("checkNormalHealOnly should NEVER press F2", !keyPress.pressedKeys.contains("F2"))
    test("Only one key should be pressed", keyPress.pressedKeys.count == 1)
    
    // ============================================
    // TEST 2: checkCriticalAndManaWithPriority should use F2 when HP < 50%
    // ============================================
    print("\n--- TEST 2: checkCriticalAndManaWithPriority with low HP ---")
    keyPress.reset()
    healer.resetCooldown()
    
    // HP at 40% (below critical threshold)
    let result = healer.checkCriticalAndManaWithPriority(currentHP: 400, currentMana: 500)
    
    test("HP=40% should trigger critical heal", result.healType == "critical")
    test("Should press F2", keyPress.lastKey == "F2")
    test("Should NOT press F1", !keyPress.pressedKeys.contains("F1"))
    
    // ============================================
    // TEST 3: checkCriticalAndManaWithPriority should NOT use critical when HP > 50%
    // ============================================
    print("\n--- TEST 3: checkCriticalAndManaWithPriority with OK HP ---")
    keyPress.reset()
    healer.resetCooldown()
    
    // HP at 60% (above critical threshold, but needs normal heal)
    let result2 = healer.checkCriticalAndManaWithPriority(currentHP: 600, currentMana: 500)
    
    test("HP=60% (above 50%) should NOT trigger critical", result2.healType == nil)
    test("Should NOT press F2", !keyPress.pressedKeys.contains("F2"))
    test("Should NOT press any heal key", keyPress.pressedKeys.isEmpty)
    
    // ============================================
    // TEST 4: Simulate criticalIsPotion mode - full cycle
    // ============================================
    print("\n--- TEST 4: criticalIsPotion mode simulation ---")
    keyPress.reset()
    healer.resetCooldown()
    healer.criticalIsPotion = true
    
    // HP at 60% - should only trigger normal heal
    print("  Simulating HP=60%, Mana=100%:")
    _ = healer.checkCriticalAndManaWithPriority(currentHP: 600, currentMana: 500)
    healer.resetCooldown() // Reset for next check
    _ = healer.checkNormalHealOnly(currentHP: 600)
    
    test("HP=60% should trigger normal heal (F1)", keyPress.f1Count == 1)
    test("HP=60% should NOT trigger critical (F2)", keyPress.f2Count == 0)
    
    // ============================================
    // TEST 5: HP at 80% - no heal needed
    // ============================================
    print("\n--- TEST 5: HP=80% - no heal needed ---")
    keyPress.reset()
    healer.resetCooldown()
    
    _ = healer.checkCriticalAndManaWithPriority(currentHP: 800, currentMana: 500)
    healer.resetCooldown()
    _ = healer.checkNormalHealOnly(currentHP: 800)
    
    test("HP=80% should not trigger any heal", keyPress.pressedKeys.isEmpty)
    
    // ============================================
    // TEST 6: HP at 40%, Mana at 30% - critical has priority
    // ============================================
    print("\n--- TEST 6: HP=40%, Mana=30% - critical has priority ---")
    keyPress.reset()
    healer.resetCooldown()
    
    let result3 = healer.checkCriticalAndManaWithPriority(currentHP: 400, currentMana: 150)
    
    test("Low HP + Low Mana should prioritize critical heal", result3.healType == "critical")
    test("Should press F2 (critical), not F4 (mana)", keyPress.lastKey == "F2")
    test("Should NOT press F4", !keyPress.pressedKeys.contains("F4"))
    
    // ============================================
    // TEST 7: HP OK, Mana low - should restore mana
    // ============================================
    print("\n--- TEST 7: HP=80%, Mana=30% - should restore mana ---")
    keyPress.reset()
    healer.resetCooldown()
    
    let result4 = healer.checkCriticalAndManaWithPriority(currentHP: 800, currentMana: 150)
    
    test("HP OK, Mana low should restore mana", result4.manaRestored == true)
    test("Should press F4", keyPress.lastKey == "F4")
    
    // ============================================
    // TEST 8: Multiple cycles without critical
    // ============================================
    print("\n--- TEST 8: 10 cycles with HP=70% - should NEVER use critical ---")
    keyPress.reset()
    
    for i in 1...10 {
        healer.resetCooldown()
        _ = healer.checkCriticalAndManaWithPriority(currentHP: 700, currentMana: 500)
        healer.resetCooldown()
        _ = healer.checkNormalHealOnly(currentHP: 700)
    }
    
    test("10 cycles with HP=70% should trigger normal heal 10 times", keyPress.f1Count == 10)
    test("10 cycles with HP=70% should NEVER trigger critical heal", keyPress.f2Count == 0)
    
    // ============================================
    // SUMMARY
    // ============================================
    print("\n" + String(repeating: "=", count: 60))
    print("TEST RESULTS: \(passedTests) passed, \(failedTests) failed")
    print(String(repeating: "=", count: 60) + "\n")
    
    if failedTests > 0 {
        print("❌ SOME TESTS FAILED!")
    } else {
        print("✅ ALL TESTS PASSED!")
    }
}

// Run the tests
runTests()
