#!/usr/bin/env swift

import Foundation

// ============================================
// RANDOM COOLDOWN TESTS
// Tests for random cooldown implementation:
// 1. Utito Tempo: 9-12 seconds (instead of fixed 10s)
// 2. Spell CD: base - 0.1 to base + 0.15 (e.g., 0.5s -> 0.4-0.65s)
// 3. Potion CD: base - 0.1 to base + 0.2 (e.g., 0.5s -> 0.4-0.7s)
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
    var f8Count: Int { pressedKeys.filter { $0 == "F8" }.count }
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
// AUTO HEALER WITH RANDOM COOLDOWNS
// ============================================

class TestAutoHealer {
    private let keyPress: MockKeyPressService
    
    // Configurable cooldowns (base values)
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
    
    // Random cooldown tracking - each cast gets a new random cooldown
    private var currentSpellCooldownTarget: TimeInterval = 0.5
    private var currentPotionCooldownTarget: TimeInterval = 0.5
    
    // Store generated cooldowns for testing
    var lastGeneratedSpellCooldown: TimeInterval = 0.5
    var lastGeneratedPotionCooldown: TimeInterval = 0.5
    
    init(keyPress: MockKeyPressService) {
        self.keyPress = keyPress
    }
    
    // MARK: - Random Cooldown Helpers
    
    /// Generate random spell cooldown: base - 0.1 to base + 0.15
    private func randomSpellCooldown() -> TimeInterval {
        let minCooldown = max(0.1, spellCooldown - 0.1)
        let maxCooldown = spellCooldown + 0.15
        let result = Double.random(in: minCooldown...maxCooldown)
        lastGeneratedSpellCooldown = result
        return result
    }
    
    /// Generate random potion cooldown: base - 0.1 to base + 0.2
    private func randomPotionCooldown() -> TimeInterval {
        let minCooldown = max(0.1, potionCooldown - 0.1)
        let maxCooldown = potionCooldown + 0.2
        let result = Double.random(in: minCooldown...maxCooldown)
        lastGeneratedPotionCooldown = result
        return result
    }
    
    // MARK: - Cooldown Checks
    
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
    
    func getManaPercent(_ currentMana: Int) -> Double {
        guard let max = maxMana, max > 0 else { return 100.0 }
        return (Double(currentMana) / Double(max)) * 100.0
    }
    
    // Cast spell (uses spell cooldown with random variation)
    private func castSpell(_ config: HealConfig) {
        keyPress.pressKey(config.hotkey)
        lastSpellCastTime = Date()
        currentSpellCooldownTarget = randomSpellCooldown()
    }
    
    // Use potion (uses potion cooldown with random variation)
    private func usePotion(_ hotkey: String) {
        keyPress.pressKey(hotkey)
        lastPotionCastTime = Date()
        currentPotionCooldownTarget = randomPotionCooldown()
    }
    
    // MARK: - checkAndHeal (standard mode)
    
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
// AUTO COMBO WITH RANDOM UTITO DURATION
// ============================================

class TestAutoCombo {
    private let keyPress: MockKeyPressService
    
    var utitoTempoHotkey: String = "F8"
    var utitoTempoEnabled: Bool = true
    var recastUtito: Bool = true
    var isActive: Bool = false
    
    // Utito Tempo timing with random duration
    private var lastUtitoTime: Date = .distantPast
    private let utitoDurationMin: TimeInterval = 9.0   // Min random duration
    private let utitoDurationMax: TimeInterval = 12.0  // Max random duration
    private var currentUtitoDuration: TimeInterval = 10.0  // Current random duration
    
    // Store generated durations for testing
    var lastGeneratedUtitoDuration: TimeInterval = 10.0
    
    init(keyPress: MockKeyPressService) {
        self.keyPress = keyPress
    }
    
    /// Generate random Utito duration 9-12 seconds
    private func randomUtitoDuration() -> TimeInterval {
        let result = Double.random(in: utitoDurationMin...utitoDurationMax)
        lastGeneratedUtitoDuration = result
        return result
    }
    
    func reset() {
        lastUtitoTime = .distantPast
        isActive = false
    }
    
    func startCombo() {
        isActive = true
        if utitoTempoEnabled {
            keyPress.pressKey(utitoTempoHotkey)
            lastUtitoTime = Date()
            currentUtitoDuration = randomUtitoDuration()
            print("    ⚡ Utito cast, next recast in \(String(format: "%.2f", currentUtitoDuration))s")
        }
    }
    
    func checkAndRecast() {
        guard isActive && recastUtito && utitoTempoEnabled else { return }
        
        let now = Date()
        if now.timeIntervalSince(lastUtitoTime) >= currentUtitoDuration {
            keyPress.pressKey(utitoTempoHotkey)
            lastUtitoTime = now
            currentUtitoDuration = randomUtitoDuration()
            print("    ⚡ Utito RE-CAST, next in \(String(format: "%.2f", currentUtitoDuration))s")
        }
    }
    
    /// Simulate time passing by manipulating lastUtitoTime
    func simulateTimePassed(_ seconds: TimeInterval) {
        lastUtitoTime = Date().addingTimeInterval(-seconds)
    }
    
    func getCurrentDuration() -> TimeInterval {
        return currentUtitoDuration
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
    print("RUNNING RANDOM COOLDOWN TESTS")
    print(String(repeating: "=", count: 60) + "\n")
    
    let keyPress = MockKeyPressService()
    let healer = TestAutoHealer(keyPress: keyPress)
    healer.maxHP = 1000
    healer.maxMana = 500
    
    let combo = TestAutoCombo(keyPress: keyPress)
    
    // ============================================
    // TEST 1: Spell cooldown generates random values in correct range
    // ============================================
    print("\n--- TEST 1: Spell cooldown random range (0.4s - 0.65s for base 0.5s) ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.spellCooldown = 0.5
    
    var spellCooldowns: [TimeInterval] = []
    
    // Generate multiple spell cooldowns
    for _ in 1...20 {
        healer.resetAllCooldowns()
        _ = healer.checkAndHeal(currentHP: 600)  // HP 60% - normal heal
        spellCooldowns.append(healer.lastGeneratedSpellCooldown)
    }
    
    let minSpellCD = spellCooldowns.min() ?? 0
    let maxSpellCD = spellCooldowns.max() ?? 0
    
    print("  Generated spell cooldowns: min=\(String(format: "%.3f", minSpellCD))s, max=\(String(format: "%.3f", maxSpellCD))s")
    
    test("All spell cooldowns >= 0.4s", spellCooldowns.allSatisfy { $0 >= 0.4 })
    test("All spell cooldowns <= 0.65s", spellCooldowns.allSatisfy { $0 <= 0.65 })
    test("Spell cooldowns have variation (not all same)", Set(spellCooldowns.map { Int($0 * 1000) }).count > 1)
    
    // ============================================
    // TEST 2: Potion cooldown generates random values in correct range
    // ============================================
    print("\n--- TEST 2: Potion cooldown random range (0.4s - 0.7s for base 0.5s) ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.potionCooldown = 0.5
    
    var potionCooldowns: [TimeInterval] = []
    
    // Generate multiple potion cooldowns
    for _ in 1...20 {
        healer.resetAllCooldowns()
        _ = healer.checkAndRestoreMana(currentMana: 200)  // Mana 40%
        potionCooldowns.append(healer.lastGeneratedPotionCooldown)
    }
    
    let minPotionCD = potionCooldowns.min() ?? 0
    let maxPotionCD = potionCooldowns.max() ?? 0
    
    print("  Generated potion cooldowns: min=\(String(format: "%.3f", minPotionCD))s, max=\(String(format: "%.3f", maxPotionCD))s")
    
    test("All potion cooldowns >= 0.4s", potionCooldowns.allSatisfy { $0 >= 0.4 })
    test("All potion cooldowns <= 0.7s", potionCooldowns.allSatisfy { $0 <= 0.7 })
    test("Potion cooldowns have variation (not all same)", Set(potionCooldowns.map { Int($0 * 1000) }).count > 1)
    
    // ============================================
    // TEST 3: Utito Tempo duration generates random values (9-12s)
    // ============================================
    print("\n--- TEST 3: Utito Tempo random duration (9s - 12s) ---")
    keyPress.reset()
    
    var utitoDurations: [TimeInterval] = []
    
    // Generate multiple Utito durations
    for _ in 1...20 {
        combo.reset()
        combo.startCombo()
        utitoDurations.append(combo.lastGeneratedUtitoDuration)
    }
    
    let minUtitoDur = utitoDurations.min() ?? 0
    let maxUtitoDur = utitoDurations.max() ?? 0
    
    print("  Generated Utito durations: min=\(String(format: "%.2f", minUtitoDur))s, max=\(String(format: "%.2f", maxUtitoDur))s")
    
    test("All Utito durations >= 9.0s", utitoDurations.allSatisfy { $0 >= 9.0 })
    test("All Utito durations <= 12.0s", utitoDurations.allSatisfy { $0 <= 12.0 })
    test("Utito durations have variation", Set(utitoDurations.map { Int($0 * 100) }).count > 1)
    
    // ============================================
    // TEST 4: New random cooldown generated after each spell cast
    // ============================================
    print("\n--- TEST 4: New random cooldown after each spell cast ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    
    var previousCooldown: TimeInterval = 0.0
    var differentCooldowns = 0
    
    for i in 1...10 {
        healer.resetAllCooldowns()
        _ = healer.checkAndHeal(currentHP: 600)
        
        if i > 1 && healer.lastGeneratedSpellCooldown != previousCooldown {
            differentCooldowns += 1
        }
        previousCooldown = healer.lastGeneratedSpellCooldown
    }
    
    print("  Different cooldowns generated: \(differentCooldowns)/9")
    test("Random cooldowns are generated (at least 3 different)", differentCooldowns >= 3)
    
    // ============================================
    // TEST 5: Utito recast uses new random duration each time
    // ============================================
    print("\n--- TEST 5: New random duration after each Utito recast ---")
    keyPress.reset()
    combo.reset()
    combo.startCombo()
    
    var utitoDurationsRecast: [TimeInterval] = []
    utitoDurationsRecast.append(combo.getCurrentDuration())
    
    // Simulate multiple recasts
    for _ in 1...5 {
        combo.simulateTimePassed(15.0)  // Simulate 15s passed (exceeds max 12s)
        combo.checkAndRecast()
        utitoDurationsRecast.append(combo.getCurrentDuration())
    }
    
    let uniqueDurations = Set(utitoDurationsRecast.map { Int($0 * 100) }).count
    print("  Unique Utito durations: \(uniqueDurations)/6")
    test("Utito durations vary between recasts", uniqueDurations >= 2)
    
    // ============================================
    // TEST 6: Minimum cooldown protection (can't go below 0.1s)
    // ============================================
    print("\n--- TEST 6: Minimum cooldown protection ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.spellCooldown = 0.05  // Very low base cooldown
    
    var lowBaseCooldowns: [TimeInterval] = []
    
    for _ in 1...20 {
        healer.resetAllCooldowns()
        _ = healer.checkAndHeal(currentHP: 600)
        lowBaseCooldowns.append(healer.lastGeneratedSpellCooldown)
    }
    
    let minLowCD = lowBaseCooldowns.min() ?? 0
    print("  Min cooldown with 0.05s base: \(String(format: "%.3f", minLowCD))s")
    
    test("Cooldown never goes below 0.1s", lowBaseCooldowns.allSatisfy { $0 >= 0.1 })
    
    // Reset base cooldown
    healer.spellCooldown = 0.5
    
    // ============================================
    // TEST 7: Different base values produce different ranges
    // ============================================
    print("\n--- TEST 7: Different base values produce correct ranges ---")
    keyPress.reset()
    
    // Test with base 1.0s spell cooldown (expected range: 0.9s - 1.15s)
    healer.spellCooldown = 1.0
    var highBaseCooldowns: [TimeInterval] = []
    
    for _ in 1...20 {
        healer.resetAllCooldowns()
        _ = healer.checkAndHeal(currentHP: 600)
        highBaseCooldowns.append(healer.lastGeneratedSpellCooldown)
    }
    
    let minHighCD = highBaseCooldowns.min() ?? 0
    let maxHighCD = highBaseCooldowns.max() ?? 0
    
    print("  Base 1.0s: min=\(String(format: "%.3f", minHighCD))s, max=\(String(format: "%.3f", maxHighCD))s")
    
    test("Base 1.0s: all cooldowns >= 0.9s", highBaseCooldowns.allSatisfy { $0 >= 0.9 })
    test("Base 1.0s: all cooldowns <= 1.15s", highBaseCooldowns.allSatisfy { $0 <= 1.15 })
    
    // Reset
    healer.spellCooldown = 0.5
    
    // ============================================
    // TEST 8: Spell and potion cooldowns are still independent
    // ============================================
    print("\n--- TEST 8: Random cooldowns still independent ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    
    // Cast a spell
    _ = healer.checkAndHeal(currentHP: 600)
    
    test("Spell cast presses F1", keyPress.f1Count == 1)
    test("Spell cooldown is active", healer.isSpellOnCooldown)
    test("Potion cooldown is NOT active", !healer.isPotionOnCooldown)
    
    // Mana should still work (different cooldown)
    _ = healer.checkAndRestoreMana(currentMana: 200)
    
    test("Mana works while spell on cooldown", keyPress.f4Count == 1)
    test("Both spell and potion cooldowns now active", healer.isSpellOnCooldown && healer.isPotionOnCooldown)
    
    // ============================================
    // TEST 9: Utito recast timing respects random duration
    // ============================================
    print("\n--- TEST 9: Utito recast respects random duration ---")
    keyPress.reset()
    combo.reset()
    combo.startCombo()
    
    let initialCount = keyPress.f8Count
    let currentDuration = combo.getCurrentDuration()
    
    // Simulate time less than current duration - should NOT recast
    combo.simulateTimePassed(currentDuration - 1.0)
    combo.checkAndRecast()
    
    test("No recast before duration expires", keyPress.f8Count == initialCount)
    
    // Simulate time greater than current duration - should recast
    combo.simulateTimePassed(currentDuration + 0.5)
    combo.checkAndRecast()
    
    test("Recast after duration expires", keyPress.f8Count == initialCount + 1)
    
    // ============================================
    // TEST 10: Statistical distribution test
    // ============================================
    print("\n--- TEST 10: Statistical distribution (randomness quality) ---")
    keyPress.reset()
    healer.resetAllCooldowns()
    healer.spellCooldown = 0.5
    
    var cooldownBuckets: [Int: Int] = [:]  // Bucket by 50ms
    
    for _ in 1...100 {
        healer.resetAllCooldowns()
        _ = healer.checkAndHeal(currentHP: 600)
        let bucket = Int(healer.lastGeneratedSpellCooldown * 20)  // 0.95s buckets
        cooldownBuckets[bucket, default: 0] += 1
    }
    
    print("  Distribution (50ms buckets):")
    for bucket in cooldownBuckets.keys.sorted() {
        let rangeStart = Double(bucket) * 0.05
        let rangeEnd = rangeStart + 0.05
        print("    \(String(format: "%.2f", rangeStart))-\(String(format: "%.2f", rangeEnd))s: \(cooldownBuckets[bucket]!) samples")
    }
    
    // Expect at least 3 different buckets for good distribution
    test("Good distribution (at least 3 buckets)", cooldownBuckets.count >= 3)
    
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
