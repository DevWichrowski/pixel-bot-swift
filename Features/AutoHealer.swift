import Foundation

/// Auto healer managing normal heal, critical heal, and mana restoration
class AutoHealer {
    /// Configurable cooldowns
    var spellCooldown: TimeInterval = 0.5   // For heal spells (normal + critical when not potion)
    var potionCooldown: TimeInterval = 0.5  // For potions (mana + critical when is potion)

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

    var spiritPotionHeal: Bool = false
    var spiritPotionHotkey: String = "F3"
    var spiritPotionThreshold: Int = 40

    /// Separate cooldown tracking
    private var lastSpellCastTime: Date = .distantPast   // For normal + critical (non-potion mode)
    private var lastPotionCastTime: Date = .distantPast  // For mana + critical (potion mode)

    /// Random cooldown tracking - each cast gets a new random cooldown
    private var currentSpellCooldownTarget: TimeInterval = 0.5
    private var currentPotionCooldownTarget: TimeInterval = 0.5

    /// Reaction delay — simulates human reaction time on first heal after HP drops
    private var isReacting: Bool = false          // Currently in "reaction" wait
    private var reactionEndTime: Date = .distantPast  // When the reaction delay expires
    private var wasHPBelowThreshold: Bool = false // Tracks if we were already healing

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

    // MARK: - Random Cooldown Helpers

    /// Generate random spell cooldown using log-normal distribution
    /// Median is slightly above base, with right-skewed tail
    private func randomSpellCooldown() -> TimeInterval {
        humanRandom(median: spellCooldown + 0.08, spread: 0.3, min: spellCooldown, max: spellCooldown + 0.4)
    }

    /// Generate random potion cooldown using log-normal distribution
    private func randomPotionCooldown() -> TimeInterval {
        humanRandom(median: potionCooldown + 0.06, spread: 0.3, min: potionCooldown, max: potionCooldown + 0.35)
    }

    /// Generate random reaction delay (simulates human noticing HP dropped)
    /// Log-normal: most reactions ~180ms, occasional longer delays
    private func randomReactionDelay() -> TimeInterval {
        humanRandom(median: 0.18, spread: 0.35, min: 0.1, max: 0.4)
    }

    /// Check if reaction delay is needed before healing.
    /// Returns true if healing is allowed (no delay or delay has passed).
    private func checkReactionDelay(hpBelowThreshold: Bool) -> Bool {
        if !hpBelowThreshold {
            // HP is fine — reset reaction state
            wasHPBelowThreshold = false
            isReacting = false
            return true
        }

        if wasHPBelowThreshold {
            // Already been healing — no extra delay
            return true
        }

        // First time HP dropped below threshold — start reaction
        if !isReacting {
            isReacting = true
            reactionEndTime = Date().addingTimeInterval(randomReactionDelay())
            return false
        }

        // Waiting for reaction delay to pass
        if Date() < reactionEndTime {
            return false
        }

        // Reaction delay passed — allow healing
        wasHPBelowThreshold = true
        isReacting = false
        return true
    }

    // MARK: - Cooldown Checks

    var isSpellOnCooldown: Bool {
        Date().timeIntervalSince(lastSpellCastTime) < currentSpellCooldownTarget
    }

    var isPotionOnCooldown: Bool {
        Date().timeIntervalSince(lastPotionCastTime) < currentPotionCooldownTarget
    }

    // MARK: - Healing

    /// Check if healing is needed and cast if possible (standard mode - criticalIsPotion = false)
    /// Both normal and critical heal use spell cooldown
    /// Returns: "critical", "normal", or nil
    @discardableResult
    func checkAndHeal(currentHP: Int) -> String? {
        autoDetectMaxHP(currentHP)

        guard maxHP != nil else { return nil }

        let hpPercent = getHPPercent(currentHP)
        let needsHeal = (heal.enabled && hpPercent < Double(heal.threshold)) ||
                        (criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold))

        // Reaction delay — simulate human noticing HP dropped
        guard checkReactionDelay(hpBelowThreshold: needsHeal) else { return nil }

        guard !isSpellOnCooldown else { return nil }

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

    /// Check only normal heal (skip critical) - used when criticalIsPotion mode is enabled
    /// In that mode, critical heal is handled by checkCriticalAndManaWithPriority
    /// Uses spell cooldown
    @discardableResult
    func checkNormalHealOnly(currentHP: Int) -> Bool {
        autoDetectMaxHP(currentHP)

        guard maxHP != nil else { return false }

        let hpPercent = getHPPercent(currentHP)
        let needsHeal = heal.enabled && hpPercent < Double(heal.threshold)

        // Reaction delay — simulate human noticing HP dropped
        // Only trigger if not already reacting from another heal check this tick
        if !wasHPBelowThreshold {
            guard checkReactionDelay(hpBelowThreshold: needsHeal) else { return false }
        }

        guard !isSpellOnCooldown else { return false }

        // Only normal heal - critical is handled separately (potion)
        if needsHeal {
            castSpell(heal)
            return true
        }

        return false
    }

    /// Cast a spell (uses spell cooldown with random variation)
    /// Cooldown is only updated if the key press was actually sent.
    private func castSpell(_ config: HealConfig) {
        guard keyPress.pressKey(config.hotkey, urgent: true) else { return }
        lastSpellCastTime = Date()
        currentSpellCooldownTarget = randomSpellCooldown()
    }

    /// Use a potion (uses potion cooldown with random variation)
    /// Cooldown is only updated if the key press was actually sent.
    private func usePotion(_ hotkey: String) {
        guard keyPress.pressKey(hotkey, urgent: true) else { return }
        lastPotionCastTime = Date()
        currentPotionCooldownTarget = randomPotionCooldown()
    }

    // MARK: - Mana Restoration

    /// Check if mana restore is needed (uses potion cooldown)
    @discardableResult
    func checkAndRestoreMana(currentMana: Int) -> Bool {
        autoDetectMaxMana(currentMana)

        guard maxMana != nil else { return false }

        guard !isPotionOnCooldown else { return false }

        let manaPercent = getManaPercent(currentMana)

        if manaRestore.enabled && manaPercent < Double(manaRestore.threshold) {
            usePotion(manaRestore.hotkey)
            print("🔷 Mana restore: \(manaRestore.hotkey) (threshold: \(manaRestore.threshold)%)")
            return true
        }

        return false
    }

    // MARK: - Critical Is Potion Mode

    /// Check both critical heal and mana with critical priority
    /// Used when criticalIsPotion is true - both use potion cooldown
    func checkCriticalAndManaWithPriority(currentHP: Int, currentMana: Int) -> (healType: String?, manaRestored: Bool) {
        autoDetectMaxHP(currentHP)
        autoDetectMaxMana(currentMana)

        let hpPercent = maxHP != nil ? getHPPercent(currentHP) : 100.0
        let manaPercent = maxMana != nil ? getManaPercent(currentMana) : 100.0
        let needsHeal = criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold)

        // Reaction delay for critical heal
        guard checkReactionDelay(hpBelowThreshold: needsHeal) else { return (nil, false) }

        guard !isPotionOnCooldown else { return (nil, false) }

        // Priority 1: Critical heal (life-saving) - uses potion
        if needsHeal {
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

    // MARK: - Spirit Potion Heal Mode

    /// Inter-action delay: random 80-260ms gap between spell and potion in same cycle
    private func randomInterActionDelay() -> TimeInterval {
        let baseGap = 0.08
        let jitter = Double.random(in: 0...0.12) * Double.random(in: 0.5...1.5)
        return baseGap + jitter
    }

    func checkSpiritPotionHeal(currentHP: Int, currentMana: Int) -> (spellCast: Bool, potionUsed: Bool) {
        autoDetectMaxHP(currentHP)
        autoDetectMaxMana(currentMana)

        guard maxHP != nil else { return (false, false) }

        let hpPercent = getHPPercent(currentHP)
        let needsCriticalHeal = criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold)
        let needsSpiritPotion = hpPercent < Double(spiritPotionThreshold)

        // Nothing to do — don't touch reaction state (normal heal may need it)
        guard needsCriticalHeal || needsSpiritPotion else { return (false, false) }

        // Single reaction delay gates both checks (human reacts once to HP dropping)
        guard checkReactionDelay(hpBelowThreshold: true) else { return (false, false) }

        var spellCast = false
        var potionUsed = false

        // Critical heal spell (independent threshold)
        if needsCriticalHeal && !isSpellOnCooldown {
            castSpell(criticalHeal)
            spellCast = true
        }

        // Spirit potion (independent threshold)
        if needsSpiritPotion && !isPotionOnCooldown {
            if spellCast {
                // Both firing same cycle — add human-like delay between key presses
                let delay = randomInterActionDelay()
                Thread.sleep(forTimeInterval: delay)
            }
            usePotion(spiritPotionHotkey)
            print("🧪 Spirit Potion used (HP: \(Int(hpPercent))% < \(spiritPotionThreshold)%)")
            potionUsed = true
        }

        return (spellCast, potionUsed)
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

    func setSpiritPotionThreshold(_ value: Int) {
        if (1...100).contains(value) {
            spiritPotionThreshold = value
        }
    }
}
