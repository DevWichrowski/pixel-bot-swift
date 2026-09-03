import Foundation

/// Auto healer managing normal heal, critical heal, and mana restoration
class AutoHealer {
    static let healingGroupCooldown: TimeInterval = 1.0

    /// Kept as a source-compatible read-only view of the fixed healing group cooldown.
    var spellCooldown: TimeInterval {
        get { Self.healingGroupCooldown }
        set { _ = newValue }
    }
    var potionCooldown: TimeInterval = 0.5  // For potions (mana + critical when is potion)

    private let keyPress: any KeyPressServicing
    private let healingSpellKeyPressGroup = KeyPressRequestGroup()
    private let hpPotionKeyPressGroup = KeyPressRequestGroup()
    private let manaPotionKeyPressGroup = KeyPressRequestGroup()
    private let uptimeProvider: () -> TimeInterval
    private let diagnosticLogger: DiagnosticLogging?
    private let decisionLogLock = NSLock()
    private var lastLoggedDecisionSignature: String?

    /// Max HP and Mana (auto-detected or manually set)
    var maxHP: Int?
    var maxMana: Int?

    /// Heal configurations
    var heal = HealConfig(enabled: true, threshold: 75, hotkey: "F1")
    var criticalHeal = HealConfig(enabled: true, threshold: 50, hotkey: "F2")
    var manaRestore = HealConfig(enabled: true, threshold: 60, hotkey: "F4")

    /// Critical heal is a potion mode - shares cooldown with mana, has priority
    var criticalIsPotion: Bool = false

    var spiritPotionHeal: Bool = false {
        didSet {
            if !spiritPotionHeal {
                cancelPendingHPDependentActions()
            }
        }
    }
    var spiritPotionHotkey: String = "F3"
    var spiritPotionThreshold: Int = 40

    private enum HealingPriority: Int {
        case normal
        case critical
    }

    private struct HealingRequestState {
        let requestID: UUID
        let priority: HealingPriority
        var didSendKeyDown: Bool
    }

    private let healingStateLock = NSLock()
    private var healingRequest: HealingRequestState?
    private var healingEnqueueInProgress = false
    private var lastHealingKeyDownUptime: TimeInterval?

    private enum PotionKind {
        case hp
        case mana
    }

    private struct PotionRequestState {
        let requestID: UUID
        let kind: PotionKind
        var didSendKeyDown: Bool
    }

    private let potionStateLock = NSLock()
    private var potionRequest: PotionRequestState?
    private var potionEnqueueKind: PotionKind?
    private var lastPotionKeyDownUptime: TimeInterval?
    private var currentPotionCooldownTarget: TimeInterval = 0.5

    init(
        keyPress: any KeyPressServicing = KeyPressService.shared,
        delayedActionQueue: DispatchQueue = .main,
        reactionDelayOverride: (() -> TimeInterval)? = nil,
        interActionDelayOverride: (() -> TimeInterval)? = nil,
        uptimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        diagnosticLogger: DiagnosticLogging? = nil
    ) {
        self.keyPress = keyPress
        _ = delayedActionQueue
        _ = reactionDelayOverride
        _ = interActionDelayOverride
        self.uptimeProvider = uptimeProvider
        self.diagnosticLogger = diagnosticLogger
    }

    deinit {
        cancelPendingActions()
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

    // MARK: - Cooldown helpers

    /// Generate random potion cooldown using log-normal distribution
    private func randomPotionCooldown() -> TimeInterval {
        humanRandom(median: potionCooldown + 0.06, spread: 0.3, min: potionCooldown, max: potionCooldown + 0.35)
    }

    // MARK: - Cooldown Checks

    var isSpellOnCooldown: Bool {
        healingStateLock.withLock {
            healingEnqueueInProgress || healingRequest != nil || healingCooldownRemainingLocked() > 0
        }
    }

    var healingCooldownRemaining: TimeInterval {
        healingStateLock.withLock { healingCooldownRemainingLocked() }
    }

    var isPotionOnCooldown: Bool {
        potionStateLock.withLock {
            potionEnqueueKind != nil ||
                potionRequest != nil ||
                potionCooldownRemainingLocked() > 0
        }
    }

    // MARK: - Healing

    /// Check if healing is needed and cast if possible (standard mode - criticalIsPotion = false)
    /// Both normal and critical heal use spell cooldown
    /// Returns: "critical", "normal", or nil
    @discardableResult
    func checkAndHeal(currentHP: Int, validFor: TimeInterval? = nil) -> String? {
        autoDetectMaxHP(currentHP)

        guard maxHP != nil else { return nil }

        let hpPercent = getHPPercent(currentHP)
        // Critical heal has priority
        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            return castSpell(
                criticalHeal,
                priority: .critical,
                validFor: validFor
            ) ? "critical" : nil
        }

        // Normal heal
        if heal.enabled && hpPercent < Double(heal.threshold) {
            return castSpell(heal, priority: .normal, validFor: validFor) ? "normal" : nil
        }

        resetHealingDecisionLog()
        return nil
    }

    /// Check only normal heal (skip critical) - used when criticalIsPotion mode is enabled
    /// In that mode, critical heal is handled by checkCriticalAndManaWithPriority
    /// Uses spell cooldown
    @discardableResult
    func checkNormalHealOnly(currentHP: Int, validFor: TimeInterval? = nil) -> Bool {
        autoDetectMaxHP(currentHP)

        guard maxHP != nil else { return false }

        let hpPercent = getHPPercent(currentHP)
        // Only normal heal - critical is handled separately (potion)
        if heal.enabled && hpPercent < Double(heal.threshold) {
            return castSpell(heal, priority: .normal, validFor: validFor)
        }

        resetHealingDecisionLog()
        return false
    }

    /// Queues one healing spell. The cooldown starts only when keyDown is sent.
    @discardableResult
    private func castSpell(
        _ config: HealConfig,
        priority: HealingPriority,
        validFor: TimeInterval?
    ) -> Bool {
        let existing = healingStateLock.withLock { healingRequest }
        if let existing {
            guard !existing.didSendKeyDown,
                  existing.priority == .normal,
                  priority == .critical else {
                logHealingDecision("pending", priority: priority)
                return false
            }
            keyPress.cancelPendingRequests(in: healingSpellKeyPressGroup)
        }

        let canEnqueue = healingStateLock.withLock { () -> Bool in
            guard healingRequest == nil,
                  !healingEnqueueInProgress,
                  healingCooldownRemainingLocked() <= 0 else {
                return false
            }
            healingEnqueueInProgress = true
            return true
        }
        guard canEnqueue else {
            logHealingDecision("cooldown", priority: priority)
            return false
        }

        let accepted = keyPress.pressKey(
            config.hotkey,
            priority: .healing,
            group: healingSpellKeyPressGroup,
            validUntil: validFor.map { uptimeProvider() + max(0, $0) },
            lifecycle: { [weak self] event in
                self?.handleHealingLifecycle(event, priority: priority)
            }
        )
        if !accepted {
            healingStateLock.withLock {
                healingEnqueueInProgress = false
            }
            logHealingDecision("failed", priority: priority)
            return false
        }
        logHealingDecision(existing == nil ? "enqueued" : "replaced_normal", priority: priority)
        return true
    }

    /// Enqueues one potion. Its shared cooldown starts only when keyDown is sent.
    @discardableResult
    private func usePotion(
        _ hotkey: String,
        kind: PotionKind,
        priority: KeyPressPriority,
        validUntil: TimeInterval? = nil
    ) -> Bool {
        if kind == .hp {
            let replacesPendingMana = potionStateLock.withLock {
                potionRequest?.kind == .mana && potionRequest?.didSendKeyDown == false
            }
            if replacesPendingMana {
                keyPress.cancelPendingRequests(in: manaPotionKeyPressGroup)
            }
        }

        let canEnqueue = potionStateLock.withLock { () -> Bool in
            guard potionRequest == nil,
                  potionEnqueueKind == nil,
                  potionCooldownRemainingLocked() <= 0 else {
                return false
            }
            potionEnqueueKind = kind
            return true
        }
        guard canEnqueue else { return false }

        let cooldownTarget = randomPotionCooldown()
        let group = kind == .hp ? hpPotionKeyPressGroup : manaPotionKeyPressGroup
        let accepted = keyPress.pressKey(
            hotkey,
            priority: priority,
            group: group,
            validUntil: validUntil,
            lifecycle: { [weak self] event in
                self?.handlePotionLifecycle(
                    event,
                    kind: kind,
                    cooldownTarget: cooldownTarget
                )
            }
        )
        guard accepted else {
            potionStateLock.withLock {
                if potionEnqueueKind == kind {
                    potionEnqueueKind = nil
                }
            }
            return false
        }
        return true
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
            guard usePotion(
                manaRestore.hotkey,
                kind: .mana,
                priority: .urgent
            ) else {
                return false
            }
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

        if checkCriticalPotionHeal(currentHP: currentHP) {
            return ("critical", false)
        }

        return (nil, checkAndRestoreMana(currentMana: currentMana))
    }

    @discardableResult
    func checkCriticalPotionHeal(
        currentHP: Int,
        validFor: TimeInterval? = nil
    ) -> Bool {
        autoDetectMaxHP(currentHP)
        guard maxHP != nil,
              criticalHeal.enabled,
              getHPPercent(currentHP) < Double(criticalHeal.threshold) else {
            return false
        }
        return usePotion(
            criticalHeal.hotkey,
            kind: .hp,
            priority: .healing,
            validUntil: validFor.map { uptimeProvider() + max(0, $0) }
        )
    }

    // MARK: - Spirit Potion Heal Mode

    func checkSpiritPotionHeal(currentHP: Int, currentMana: Int) -> (spellCast: Bool, potionUsed: Bool) {
        autoDetectMaxMana(currentMana)
        return checkSpiritPotionHeal(currentHP: currentHP)
    }

    func checkSpiritPotionHeal(
        currentHP: Int,
        validFor: TimeInterval? = nil
    ) -> (spellCast: Bool, potionUsed: Bool) {
        guard spiritPotionHeal else { return (false, false) }

        autoDetectMaxHP(currentHP)

        guard maxHP != nil else { return (false, false) }

        let hpPercent = getHPPercent(currentHP)
        let needsCriticalHeal = criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold)
        let needsSpiritPotion = hpPercent < Double(spiritPotionThreshold)

        guard needsCriticalHeal || needsSpiritPotion else { return (false, false) }

        var spellCast = false
        var potionUsed = false
        let validUntil = validFor.map { uptimeProvider() + max(0, $0) }

        // Critical heal spell (independent threshold)
        if needsCriticalHeal {
            spellCast = castSpell(
                criticalHeal,
                priority: .critical,
                validFor: validFor
            )
        }

        // Spirit potion (independent threshold)
        if needsSpiritPotion {
            potionUsed = usePotion(
                spiritPotionHotkey,
                kind: .hp,
                priority: .healing,
                validUntil: validUntil
            )
            if potionUsed {
                print("🧪 Spirit Potion used (HP: \(Int(hpPercent))% < \(spiritPotionThreshold)%)")
            }
        }

        return (spellCast, potionUsed)
    }

    func cancelPendingActions() {
        keyPress.cancelPendingRequests(in: healingSpellKeyPressGroup)
        keyPress.cancelPendingRequests(in: hpPotionKeyPressGroup)
        keyPress.cancelPendingRequests(in: manaPotionKeyPressGroup)
    }

    func cancelPendingHealing() {
        keyPress.cancelPendingRequests(in: healingSpellKeyPressGroup)
    }

    func cancelPendingHPDependentActions() {
        keyPress.cancelPendingRequests(in: healingSpellKeyPressGroup)
        keyPress.cancelPendingRequests(in: hpPotionKeyPressGroup)
    }

    // MARK: - Toggle methods

    func toggleHeal(_ enabled: Bool) {
        heal.enabled = enabled
        if !enabled {
            keyPress.cancelPendingRequests(in: healingSpellKeyPressGroup)
        }
    }

    func toggleCriticalHeal(_ enabled: Bool) {
        criticalHeal.enabled = enabled
        if !enabled {
            keyPress.cancelPendingRequests(in: healingSpellKeyPressGroup)
            keyPress.cancelPendingRequests(in: hpPotionKeyPressGroup)
        }
    }

    func toggleManaRestore(_ enabled: Bool) {
        manaRestore.enabled = enabled
        if !enabled {
            keyPress.cancelPendingRequests(in: manaPotionKeyPressGroup)
        }
    }

    private func handleHealingLifecycle(
        _ event: KeyPressLifecycleEvent,
        priority: HealingPriority
    ) {
        healingStateLock.withLock {
            switch event.phase {
            case .queued:
                healingEnqueueInProgress = false
                healingRequest = HealingRequestState(
                    requestID: event.requestID,
                    priority: priority,
                    didSendKeyDown: false
                )
            case .keyDown:
                guard healingRequest?.requestID == event.requestID else { return }
                healingRequest?.didSendKeyDown = true
                lastHealingKeyDownUptime = event.timestamp
            case .keyUp, .cancelled, .failed:
                guard healingRequest?.requestID == event.requestID else { return }
                healingRequest = nil
                healingEnqueueInProgress = false
            }
        }
    }

    private func healingCooldownRemainingLocked() -> TimeInterval {
        guard let lastHealingKeyDownUptime else { return 0 }
        return max(
            0,
            Self.healingGroupCooldown - (uptimeProvider() - lastHealingKeyDownUptime)
        )
    }

    private func handlePotionLifecycle(
        _ event: KeyPressLifecycleEvent,
        kind: PotionKind,
        cooldownTarget: TimeInterval
    ) {
        potionStateLock.withLock {
            switch event.phase {
            case .queued:
                potionEnqueueKind = nil
                potionRequest = PotionRequestState(
                    requestID: event.requestID,
                    kind: kind,
                    didSendKeyDown: false
                )
            case .keyDown:
                guard potionRequest?.requestID == event.requestID else { return }
                potionRequest?.didSendKeyDown = true
                lastPotionKeyDownUptime = event.timestamp
                currentPotionCooldownTarget = cooldownTarget
            case .keyUp, .cancelled, .failed:
                guard potionRequest?.requestID == event.requestID else { return }
                potionRequest = nil
                potionEnqueueKind = nil
            }
        }
    }

    private func potionCooldownRemainingLocked() -> TimeInterval {
        guard let lastPotionKeyDownUptime else { return 0 }
        return max(
            0,
            currentPotionCooldownTarget - (uptimeProvider() - lastPotionKeyDownUptime)
        )
    }

    private func logHealingDecision(_ decision: String, priority: HealingPriority) {
        let healing = priority == .critical ? "critical" : "normal"
        let signature = "\(decision):\(healing)"
        let shouldLog = decisionLogLock.withLock { () -> Bool in
            guard lastLoggedDecisionSignature != signature else { return false }
            lastLoggedDecisionSignature = signature
            return true
        }
        guard shouldLog else { return }

        diagnosticLogger?.log("healer_decision", fields: [
            "decision": .string(decision),
            "healing": .string(healing),
            "remainingCooldownMs": .double(healingCooldownRemaining * 1_000),
        ])
    }

    private func resetHealingDecisionLog() {
        decisionLogLock.withLock {
            lastLoggedDecisionSignature = nil
        }
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
