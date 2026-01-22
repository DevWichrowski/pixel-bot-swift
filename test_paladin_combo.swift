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
}

// ============================================
// TEST AUTO COMBO WITH PALADIN COMBO
// ============================================

class TestAutoCombo {
    private let keyPress: MockKeyPressService
    
    var comboHotkey: String = "2"
    var startStopHotkey: String = "v"
    var lootOnStop: Bool = true
    var autoLootHotkey: String = "space"
    
    var utitoTempoHotkey: String = "F9"
    var utitoTempoEnabled: Bool = false {
        didSet {
            if utitoTempoEnabled && paladinComboEnabled {
                paladinComboEnabled = false
            }
        }
    }
    var recastUtito: Bool = false
    
    var paladinComboEnabled: Bool = false {
        didSet {
            if paladinComboEnabled && utitoTempoEnabled {
                utitoTempoEnabled = false
            }
        }
    }
    
    var isActive: Bool = false
    var enabled: Bool = false
    
    private let comboIntervalMin: TimeInterval = 2.0
    private let comboIntervalMax: TimeInterval = 2.1
    private var nextInterval: TimeInterval = 2.0
    private var lastPressTime: Date = .distantPast
    
    private var lastUtitoTime: Date = .distantPast
    private let utitoDuration: TimeInterval = 10.0
    
    init(keyPress: MockKeyPressService) {
        self.keyPress = keyPress
        randomizeInterval()
    }
    
    private func randomizeInterval() {
        nextInterval = Double.random(in: comboIntervalMin...comboIntervalMax)
    }
    
    func toggle(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled {
            isActive = false
        }
    }
    
    func toggleActive() {
        guard enabled else { return }
        
        let wasActive = isActive
        isActive = !isActive
        
        if isActive {
            randomizeInterval()
            
            if utitoTempoEnabled {
                keyPress.pressKey(utitoTempoHotkey)
                lastUtitoTime = Date()
                let delay = Double.random(in: 0.2...0.3)
                lastPressTime = Date().addingTimeInterval(-nextInterval + delay)
            } else {
                lastPressTime = .distantPast
            }
        } else {
            if wasActive && lootOnStop {
                keyPress.pressKey(autoLootHotkey)
            }
        }
    }
    
    func start() {
        guard enabled else { return }
        isActive = true
        randomizeInterval()
        
        if utitoTempoEnabled {
            keyPress.pressKey(utitoTempoHotkey)
            lastUtitoTime = Date()
            let delay = Double.random(in: 0.2...0.3)
            lastPressTime = Date().addingTimeInterval(-nextInterval + delay)
        } else {
            lastPressTime = .distantPast
        }
    }
    
    func checkAndPress() {
        guard enabled && isActive else { return }
        
        let now = Date()
        
        if recastUtito && utitoTempoEnabled {
            if now.timeIntervalSince(lastUtitoTime) >= utitoDuration {
                keyPress.pressKey(utitoTempoHotkey)
                lastUtitoTime = now
            }
        }
        
        if !paladinComboEnabled && now.timeIntervalSince(lastPressTime) >= nextInterval {
            keyPress.pressKey(comboHotkey)
            lastPressTime = now
            randomizeInterval()
        }
    }
    
    func checkPaladinCombo(ammoDecreased: Bool) {
        guard enabled && isActive && paladinComboEnabled && ammoDecreased else { return }
        
        keyPress.pressKey(comboHotkey)
        print("🏹 Paladin Combo triggered (ammo decreased)")
    }
    
    func resetForTest() {
        isActive = false
        lastPressTime = .distantPast
        lastUtitoTime = .distantPast
    }
}

// ============================================
// TEST AMMO READER (simplified mock)
// ============================================

class TestAmmoReader {
    var lastAmmoValue: Int?
    var currentAmmoValue: Int?
    
    func updateAmmo(_ newValue: Int) -> Bool {
        lastAmmoValue = currentAmmoValue
        currentAmmoValue = newValue
        
        guard let last = lastAmmoValue, let current = currentAmmoValue else {
            return false
        }
        
        if last > current {
            print("🏹 Ammo decreased: \(last) → \(current)")
            return true
        }
        
        return false
    }
    
    func reset() {
        lastAmmoValue = nil
        currentAmmoValue = nil
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
    print("RUNNING PALADIN COMBO TESTS")
    print(String(repeating: "=", count: 60) + "\n")
    
    let keyPress = MockKeyPressService()
    let combo = TestAutoCombo(keyPress: keyPress)
    let ammoReader = TestAmmoReader()
    
    // ============================================
    // TEST 1: Mutual exclusivity - Paladin disables Utito
    // ============================================
    print("\n--- TEST 1: Mutual exclusivity - Paladin disables Utito ---")
    combo.resetForTest()
    combo.utitoTempoEnabled = true
    combo.paladinComboEnabled = false
    
    test("Utito starts enabled", combo.utitoTempoEnabled == true)
    test("Paladin starts disabled", combo.paladinComboEnabled == false)
    
    combo.paladinComboEnabled = true
    
    test("After enabling Paladin, Paladin is enabled", combo.paladinComboEnabled == true)
    test("After enabling Paladin, Utito is disabled", combo.utitoTempoEnabled == false)
    
    // ============================================
    // TEST 2: Mutual exclusivity - Utito disables Paladin
    // ============================================
    print("\n--- TEST 2: Mutual exclusivity - Utito disables Paladin ---")
    combo.resetForTest()
    combo.paladinComboEnabled = true
    combo.utitoTempoEnabled = false
    
    test("Paladin starts enabled", combo.paladinComboEnabled == true)
    test("Utito starts disabled", combo.utitoTempoEnabled == false)
    
    combo.utitoTempoEnabled = true
    
    test("After enabling Utito, Utito is enabled", combo.utitoTempoEnabled == true)
    test("After enabling Utito, Paladin is disabled", combo.paladinComboEnabled == false)
    
    // ============================================
    // TEST 3: Paladin Combo triggers on ammo decrease
    // ============================================
    print("\n--- TEST 3: Paladin Combo triggers on ammo decrease ---")
    keyPress.reset()
    combo.resetForTest()
    ammoReader.reset()
    combo.enabled = true
    combo.isActive = true
    combo.paladinComboEnabled = true
    combo.comboHotkey = "2"
    
    ammoReader.updateAmmo(600)
    let decreased1 = ammoReader.updateAmmo(599)
    
    test("Ammo 600->599 detected as decrease", decreased1 == true)
    
    combo.checkPaladinCombo(ammoDecreased: decreased1)
    
    test("Combo key pressed on ammo decrease", keyPress.lastKey == "2")
    test("Only one key pressed", keyPress.pressedKeys.count == 1)
    
    // ============================================
    // TEST 4: Paladin Combo does NOT trigger if ammo same
    // ============================================
    print("\n--- TEST 4: Paladin Combo does NOT trigger when ammo same ---")
    keyPress.reset()
    ammoReader.reset()
    
    ammoReader.updateAmmo(598)
    let notDecreased = ammoReader.updateAmmo(598)
    
    test("Ammo 598->598 NOT detected as decrease", notDecreased == false)
    
    combo.checkPaladinCombo(ammoDecreased: notDecreased)
    
    test("No key pressed when ammo same", keyPress.pressedKeys.isEmpty)
    
    // ============================================
    // TEST 5: Paladin Combo does NOT trigger if disabled
    // ============================================
    print("\n--- TEST 5: Paladin Combo disabled does not trigger ---")
    keyPress.reset()
    combo.resetForTest()
    ammoReader.reset()
    combo.enabled = true
    combo.isActive = true
    combo.paladinComboEnabled = false  // DISABLED
    
    ammoReader.updateAmmo(600)
    let decreased2 = ammoReader.updateAmmo(599)
    
    combo.checkPaladinCombo(ammoDecreased: decreased2)
    
    test("Paladin disabled - no combo on ammo decrease", keyPress.pressedKeys.isEmpty)
    
    // ============================================
    // TEST 6: Multiple ammo decreases trigger multiple combos (no cooldown)
    // ============================================
    print("\n--- TEST 6: Multiple decreases trigger multiple combos ---")
    keyPress.reset()
    combo.resetForTest()
    ammoReader.reset()
    combo.enabled = true
    combo.isActive = true
    combo.paladinComboEnabled = true
    combo.comboHotkey = "2"
    
    _ = ammoReader.updateAmmo(600)
    
    for i in stride(from: 599, through: 595, by: -1) {
        let decreased = ammoReader.updateAmmo(i)
        combo.checkPaladinCombo(ammoDecreased: decreased)
    }
    
    test("5 decreases = 5 combo presses", keyPress.pressedKeys.count == 5)
    test("All presses are combo key", keyPress.pressedKeys.allSatisfy { $0 == "2" })
    
    // ============================================
    // TEST 7: Ammo increase does NOT trigger combo
    // ============================================
    print("\n--- TEST 7: Ammo increase does NOT trigger combo ---")
    keyPress.reset()
    ammoReader.reset()
    combo.resetForTest()
    combo.enabled = true
    combo.isActive = true
    combo.paladinComboEnabled = true
    
    ammoReader.updateAmmo(100)
    let increased = ammoReader.updateAmmo(600)  // Ammo increased (reload)
    
    test("Ammo 100->600 NOT detected as decrease", increased == false)
    
    combo.checkPaladinCombo(ammoDecreased: increased)
    
    test("No combo on ammo increase", keyPress.pressedKeys.isEmpty)
    
    // ============================================
    // TEST 8: Paladin Combo requires active state
    // ============================================
    print("\n--- TEST 8: Paladin Combo requires active state ---")
    keyPress.reset()
    combo.resetForTest()
    ammoReader.reset()
    combo.enabled = true
    combo.isActive = false  // NOT ACTIVE
    combo.paladinComboEnabled = true
    
    ammoReader.updateAmmo(600)
    let decreased3 = ammoReader.updateAmmo(599)
    
    combo.checkPaladinCombo(ammoDecreased: decreased3)
    
    test("Inactive combo does not trigger on ammo decrease", keyPress.pressedKeys.isEmpty)
    
    // ============================================
    // TEST 9: Standard combo does NOT fire when Paladin enabled
    // ============================================
    print("\n--- TEST 9: Standard combo paused when Paladin enabled ---")
    keyPress.reset()
    combo.resetForTest()
    combo.enabled = true
    combo.isActive = true
    combo.paladinComboEnabled = true
    
    // Called without ammo decrease - should NOT press standard combo
    combo.checkAndPress()
    
    test("Standard combo does not fire with Paladin enabled", keyPress.pressedKeys.isEmpty)
    
    // ============================================
    // TEST 10: Standard combo fires when Paladin disabled
    // ============================================
    print("\n--- TEST 10: Standard combo fires when Paladin disabled ---")
    keyPress.reset()
    combo.resetForTest()
    combo.enabled = true
    combo.isActive = true
    combo.paladinComboEnabled = false
    combo.comboHotkey = "2"
    
    combo.checkAndPress()  // Should fire instantly (lastPressTime = distantPast)
    
    test("Standard combo fires with Paladin disabled", keyPress.lastKey == "2")
    
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

runTests()
