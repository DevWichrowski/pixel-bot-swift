import Foundation

/// Auto healer managing normal heal, critical heal, and mana restoration
class AutoHealer {
    /// Global cooldown between any spell (1 second)
    static let COOLDOWN: TimeInterval = 1.0
    
    private let keyPress: KeyPressService
    
    /// Max HP and Mana (auto-detected or manually set)
    var maxHP: Int?
    var maxMana: Int?
    
    /// Heal configurations
    var heal = HealConfig(enabled: true, threshold: 75, hotkey: "F1")
    var criticalHeal = HealConfig(enabled: true, threshold: 50, hotkey: "F2")
    var manaRestore = HealConfig(enabled: true, threshold: 60, hotkey: "F4")
    
    /// Critical heal is a potion mode - shares cooldown with mana, has priority
    var criticalIsPotion: Bool = false
    
    /// Cooldown tracking
    private var lastCastTime: Date = .distantPast
    
    init(keyPress: KeyPressService = .shared) {
        self.keyPress = keyPress
    }
    
    // MARK: - Max HP/Mana detection
    
    func setMaxHP(_ value: Int) {
        if value > 0 {
            maxHP = value
        }
    }
    
    func setMaxMana(_ value: Int) {
        if value > 0 {
            maxMana = value
        }
    }
    
    func autoDetectMaxHP(_ currentHP: Int) {
        if maxHP == nil && currentHP > 0 {
            maxHP = currentHP
            print("📊 Max HP auto-detected: \(currentHP)")
        }
    }
    
    func autoDetectMaxMana(_ currentMana: Int) {
        if maxMana == nil && currentMana > 0 {
            maxMana = currentMana
            print("📊 Max Mana auto-detected: \(currentMana)")
        }
    }
    
    // MARK: - Percentage calculations
    
    func getHPPercent(_ currentHP: Int) -> Double {
        guard let max = maxHP, max > 0 else { return 100.0 }
        return (Double(currentHP) / Double(max)) * 100.0
    }
    
    func getManaPercent(_ currentMana: Int) -> Double {
        guard let max = maxMana, max > 0 else { return 100.0 }
        return (Double(currentMana) / Double(max)) * 100.0
    }
    
    // MARK: - Cooldown
    
    var isOnCooldown: Bool {
        Date().timeIntervalSince(lastCastTime) < Self.COOLDOWN
    }
    
    var cooldownRemaining: TimeInterval {
        max(0, Self.COOLDOWN - Date().timeIntervalSince(lastCastTime))
    }
    
    // MARK: - Healing
    
    /// Check if healing is needed and cast if possible
    /// Returns: "critical", "normal", or nil
    @discardableResult
    func checkAndHeal(currentHP: Int) -> String? {
        autoDetectMaxHP(currentHP)
        
        guard maxHP != nil else { return nil }
        guard !isOnCooldown else { return nil }
        
        let hpPercent = getHPPercent(currentHP)
        
        // Critical heal has priority
        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            castHeal(criticalHeal)
            return "critical"
        }
        
        // Normal heal
        if heal.enabled && hpPercent < Double(heal.threshold) {
            castHeal(heal)
            return "normal"
        }
        
        return nil
    }
    
    /// Check only normal heal (skip critical) - used when criticalIsPotion mode is enabled
    /// In that mode, critical heal is handled by checkCriticalAndManaWithPriority
    @discardableResult
    func checkNormalHealOnly(currentHP: Int) -> Bool {
        autoDetectMaxHP(currentHP)
        
        guard maxHP != nil else { return false }
        guard !isOnCooldown else { return false }
        
        let hpPercent = getHPPercent(currentHP)
        
        // Only normal heal - critical is handled separately
        if heal.enabled && hpPercent < Double(heal.threshold) {
            castHeal(heal)
            return true
        }
        
        return false
    }
    
    private func castHeal(_ config: HealConfig) {
        keyPress.pressKey(config.hotkey)
        lastCastTime = Date()
    }
    
    // MARK: - Mana Restoration
    
    /// Check if mana restore is needed
    @discardableResult
    func checkAndRestoreMana(currentMana: Int) -> Bool {
        autoDetectMaxMana(currentMana)
        
        guard maxMana != nil else { return false }
        guard !isOnCooldown else { return false }
        
        let manaPercent = getManaPercent(currentMana)
        
        if manaRestore.enabled && manaPercent < Double(manaRestore.threshold) {
            keyPress.pressKey(manaRestore.hotkey)
            lastCastTime = Date()
            print("🔷 Mana restore: \(manaRestore.hotkey) (threshold: \(manaRestore.threshold)%)")
            return true
        }
        
        return false
    }
    
    // MARK: - Critical Is Potion Mode
    
    /// Check both critical heal and mana with critical priority
    /// Used when criticalIsPotion is true
    func checkCriticalAndManaWithPriority(currentHP: Int, currentMana: Int) -> (healType: String?, manaRestored: Bool) {
        autoDetectMaxHP(currentHP)
        autoDetectMaxMana(currentMana)
        
        guard !isOnCooldown else { return (nil, false) }
        
        let hpPercent = maxHP != nil ? getHPPercent(currentHP) : 100.0
        let manaPercent = maxMana != nil ? getManaPercent(currentMana) : 100.0
        
        // Priority 1: Critical heal (life-saving)
        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            castHeal(criticalHeal)
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
    
    // MARK: - Toggle methods
    
    func toggleHeal(_ enabled: Bool) {
        heal.enabled = enabled
    }
    
    func toggleCriticalHeal(_ enabled: Bool) {
        criticalHeal.enabled = enabled
    }
    
    func toggleManaRestore(_ enabled: Bool) {
        manaRestore.enabled = enabled
    }
    
    func setHealThreshold(_ value: Int) {
        if (1...100).contains(value) {
            heal.threshold = value
        }
    }
    
    func setCriticalThreshold(_ value: Int) {
        if (1...100).contains(value) {
            criticalHeal.threshold = value
        }
    }
    
    func setManaThreshold(_ value: Int) {
        if (1...100).contains(value) {
            manaRestore.threshold = value
        }
    }
}
