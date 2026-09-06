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
    private let reactionDelayProvider: () -> TimeInterval
    private let diagnosticLogger: DiagnosticLogging?
    private let decisionLogLock = NSLock()
    private var lastLoggedDecisionSignature: String?

    /// Max HP and Mana (auto-detected or manually set)
    var maxHP: Int?
    var maxMana: Int?

    /// Heal configurations
    var heal = HealConfig(enabled: true, threshold: 75, hotkey: "F1") {
        didSet { cancelPendingHealing() }
    }
    var criticalHeal = HealConfig(enabled: true, threshold: 50, hotkey: "F2") {
        didSet { cancelPendingHPDependentActions() }
    }
    var manaRestore = HealConfig(enabled: true, threshold: 60, hotkey: "F4")

    /// Critical heal is a potion mode - shares cooldown with mana, has priority
    var criticalIsPotion: Bool = false {
        didSet { if criticalIsPotion != oldValue { cancelPendingHPDependentActions() } }
    }

    var vocation: HealingVocation? {
        didSet { if vocation != oldValue { cancelPendingHealing() } }
    }

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

    private struct NormalHealingEpisode {
        let episodeID: UUID
        let startedAt: TimeInterval
        let reactionDelay: TimeInterval
        let readyAt: TimeInterval
        var bypassed: Bool
    }

    private let healingStateLock = NSLock()
    private var healingRequest: HealingRequestState?
    private var healingEnqueueInProgress = false
    private var healingConfigurationRevision: UInt64 = 0
    private var lastHealingKeyDownUptime: TimeInterval?
    private var lastHealingGroupCooldown: TimeInterval = 1
    private var actionKeyDownTimes: [HealingAction: TimeInterval] = [:]
    private var normalHealingEpisode: NormalHealingEpisode?

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
        self.reactionDelayProvider = reactionDelayOverride ?? {
            humanRandom(median: 0.090, spread: 0.3, min: 0.050, max: 0.150)
        }
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
    func checkAndHeal(currentHP: Int, validFor: TimeInterval? = nil, allowNormal: Bool = true) -> String? {
        autoDetectMaxHP(currentHP)

        cancelInvalidHPRequests(currentHP: currentHP)
        guard maxHP != nil, currentHP > 0 else { return nil }

        let hpPercent = getHPPercent(currentHP)
        // Critical heal has priority
        if criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold) {
            if castSpell(criticalHeal, priority: .critical, validFor: validFor) { return "critical" }
        }

        // Normal heal
        if allowNormal && heal.enabled && hpPercent < Double(heal.threshold) {
            return castNormalSpell(hpPercent: hpPercent, validFor: validFor) ? "normal" : nil
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

        cancelInvalidHPRequests(currentHP: currentHP)
        guard maxHP != nil, currentHP > 0 else { return false }

        let hpPercent = getHPPercent(currentHP)
        // Only normal heal - critical is handled separately (potion)
        if heal.enabled && hpPercent < Double(heal.threshold) {
            return castNormalSpell(hpPercent: hpPercent, validFor: validFor)
        }

        resetHealingDecisionLog()
        return false
    }

    /// Applies one reaction delay at the start of a continuous normal-healing episode.
    /// Once ready, the episode remains ready until HP recovers or runtime state is reset.
    @discardableResult
    private func castNormalSpell(hpPercent: Double, validFor: TimeInterval?) -> Bool {
        guard normalHealingIsReady(hpPercent: hpPercent) else { return false }
        return castSpell(heal, priority: .normal, validFor: validFor)
    }

    /// Queues one healing spell. The cooldown starts only when keyDown is sent.
    @discardableResult
    private func castSpell(
        _ config: HealConfig,
        priority: HealingPriority,
        validFor: TimeInterval?
    ) -> Bool {
        guard let action = config.action, action.isEmergencyHealing,
              action.supports(vocation: vocation) else { return false }
        let revision = healingStateLock.withLock { healingConfigurationRevision }
        let actionReady = healingStateLock.withLock { healingActionReadyLocked(action) }
        guard actionReady else { return false }
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
                  healingConfigurationRevision == revision,
                  healingActionReadyLocked(action) else {
                return false
            }
            healingEnqueueInProgress = true
            return true
        }
        guard canEnqueue else {
            logHealingDecision("cooldown", priority: priority)
            return false
        }

        let normalEpisode = priority == .normal
            ? healingStateLock.withLock { normalHealingEpisode }
            : nil
        let accepted = keyPress.pressKey(
            config.hotkey,
            priority: .healing,
            group: healingSpellKeyPressGroup,
            validUntil: uptimeProvider() + max(0, min(0.25, validFor ?? 0.25)),
            isValid: { [weak self] in
                guard let self else { return false }
                return self.healingStateLock.withLock {
                    self.healingConfigurationRevision == revision && self.healingActionReadyLocked(action)
                }
            },
            lifecycle: { [weak self] event in
                self?.handleHealingLifecycle(
                    event,
                    priority: priority,
                    action: action,
                    normalEpisode: normalEpisode
                )
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
    func checkAndRestoreMana(currentMana: Int, validFor: TimeInterval? = nil) -> Bool {
        autoDetectMaxMana(currentMana)

        guard maxMana != nil else { return false }

        guard manaRestore.enabled, getManaPercent(currentMana) < Double(manaRestore.threshold) else {
            cancelPendingManaActions()
            return false
        }
        guard !isPotionOnCooldown else { return false }

        let manaPercent = getManaPercent(currentMana)

        if manaRestore.enabled && manaPercent < Double(manaRestore.threshold) {
            guard usePotion(
                manaRestore.hotkey,
                kind: .mana,
                priority: .urgent,
                validUntil: uptimeProvider() + max(0, min(0.25, validFor ?? 0.25))
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
        cancelInvalidHPRequests(currentHP: currentHP)
        guard maxHP != nil, currentHP > 0,
              criticalHeal.enabled,
              getHPPercent(currentHP) < Double(criticalHeal.threshold) else {
            return false
        }
        return usePotion(
            criticalHeal.hotkey,
            kind: .hp,
            priority: .healing,
            validUntil: uptimeProvider() + max(0, min(0.25, validFor ?? 0.25))
        )
    }

    // MARK: - Spirit Potion Heal Mode

    func checkSpiritPotionHeal(currentHP: Int, currentMana: Int) -> (spellCast: Bool, potionUsed: Bool) {
        autoDetectMaxMana(currentMana)
        return checkSpiritPotionHeal(currentHP: currentHP)
    }

    func checkSpiritPotionHeal(
        currentHP: Int,
        validFor: TimeInterval? = nil,
        allowCritical: Bool = true,
        allowNormal: Bool = true,
        allowPotion: Bool = true
    ) -> (spellCast: Bool, potionUsed: Bool) {
        guard spiritPotionHeal else { return (false, false) }

        autoDetectMaxHP(currentHP)

        cancelInvalidHPRequests(currentHP: currentHP)
        guard maxHP != nil, currentHP > 0 else { return (false, false) }

        let hpPercent = getHPPercent(currentHP)
        let needsCriticalHeal = allowCritical && criticalHeal.enabled && hpPercent < Double(criticalHeal.threshold)
        let needsSpiritPotion = allowPotion && hpPercent < Double(spiritPotionThreshold)

        guard needsCriticalHeal || needsSpiritPotion || (allowNormal && heal.enabled && hpPercent < Double(heal.threshold)) else { return (false, false) }

        var spellCast = false
        var potionUsed = false
        let validUntil = uptimeProvider() + max(0, min(0.25, validFor ?? 0.25))

        // Critical heal spell (independent threshold)
        if needsCriticalHeal {
            spellCast = castSpell(
                criticalHeal,
                priority: .critical,
                validFor: validFor
            )
        }

        if !spellCast, allowNormal, heal.enabled, hpPercent < Double(heal.threshold) {
            spellCast = castNormalSpell(hpPercent: hpPercent, validFor: validFor)
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

    func cancelPendingManaActions() {
        keyPress.cancelPendingRequests(in: manaPotionKeyPressGroup)
    }

    /// Revoke queued decisions when the latest observation no longer supports them.
    func cancelInvalidHPRequests(currentHP: Int) {
        let percent = getHPPercent(currentHP)
        if currentHP <= 0 || percent >= Double(heal.threshold) {
            resetNormalHealingEpisode()
        }
        let pending = healingStateLock.withLock { healingRequest }
        if let pending, !pending.didSendKeyDown {
            let config = pending.priority == .critical ? criticalHeal : heal
            if currentHP <= 0 || !config.enabled || percent >= Double(config.threshold) {
                cancelPendingHealing()
            }
        }
        let needsHPPotion = currentHP > 0 && (
            (criticalIsPotion && criticalHeal.enabled && percent < Double(criticalHeal.threshold)) ||
            (spiritPotionHeal && percent < Double(spiritPotionThreshold))
        )
        if !needsHPPotion { keyPress.cancelPendingRequests(in: hpPotionKeyPressGroup) }
    }

    func cancelPendingActions() {
        cancelPendingHealing()
        keyPress.cancelPendingRequests(in: hpPotionKeyPressGroup)
        keyPress.cancelPendingRequests(in: manaPotionKeyPressGroup)
    }

    func cancelPendingHealing() {
        healingStateLock.withLock {
            healingConfigurationRevision &+= 1
            normalHealingEpisode = nil
        }
        keyPress.cancelPendingRequests(in: healingSpellKeyPressGroup)
    }

    func resetNormalHealingEpisode() {
        healingStateLock.withLock {
            normalHealingEpisode = nil
        }
    }

    func cancelPendingHPDependentActions() {
        cancelPendingHealing()
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
        priority: HealingPriority,
        action: HealingAction,
        normalEpisode: NormalHealingEpisode?
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
                lastHealingGroupCooldown = action.groupCooldown
                actionKeyDownTimes[action] = event.timestamp
            case .keyUp, .cancelled, .failed:
                guard healingRequest?.requestID == event.requestID else { return }
                healingRequest = nil
                healingEnqueueInProgress = false
            }
        }
        logHealingLifecycle(event, priority: priority, normalEpisode: normalEpisode)
    }

    private func normalHealingIsReady(hpPercent: Double) -> Bool {
        let now = uptimeProvider()
        let emergencyThreshold = Double(min(heal.threshold, criticalHeal.threshold + 5))
        let result: (ready: Bool, created: NormalHealingEpisode?) = healingStateLock.withLock {
            var created: NormalHealingEpisode?
            if normalHealingEpisode == nil {
                let delay = max(0, reactionDelayProvider())
                let episode = NormalHealingEpisode(
                    episodeID: UUID(),
                    startedAt: now,
                    reactionDelay: delay,
                    readyAt: now + delay,
                    bypassed: hpPercent <= emergencyThreshold + 0.000_001
                )
                normalHealingEpisode = episode
                created = episode
            } else if hpPercent <= emergencyThreshold + 0.000_001 {
                normalHealingEpisode?.bypassed = true
            }
            guard let episode = normalHealingEpisode else { return (false, created) }
            return (episode.bypassed || now >= episode.readyAt, created)
        }

        if let episode = result.created {
            diagnosticLogger?.log("healer_episode_started", fields: [
                "episodeID": .string(episode.episodeID.uuidString),
                "healing": .string("normal"),
                "reactionDelayMs": .double(episode.reactionDelay * 1_000),
                "bypassed": .bool(episode.bypassed),
            ])
        }
        if !result.ready {
            logHealingDecision("reaction_wait", priority: .normal)
        }
        return result.ready
    }

    private func logHealingLifecycle(
        _ event: KeyPressLifecycleEvent,
        priority: HealingPriority,
        normalEpisode: NormalHealingEpisode?
    ) {
        guard event.phase == .queued || event.phase == .keyDown else { return }
        var fields: [String: DiagnosticLogValue] = [
            "requestID": .string(event.requestID.uuidString),
            "healing": .string(priority == .critical ? "critical" : "normal"),
            "phase": .string(event.phase.rawValue),
        ]
        if let normalEpisode {
            fields["episodeID"] = .string(normalEpisode.episodeID.uuidString)
            fields["episodeStartedUptime"] = .double(normalEpisode.startedAt)
            fields["reactionDelayMs"] = .double(normalEpisode.reactionDelay * 1_000)
            fields["reactionBypassed"] = .bool(normalEpisode.bypassed)
        }
        diagnosticLogger?.log("healer_request", fields: fields)
    }

    private func healingActionReadyLocked(_ action: HealingAction) -> Bool {
        healingCooldownRemainingLocked() <= 0 &&
            (actionKeyDownTimes[action].map { uptimeProvider() - $0 >= action.individualCooldown } ?? true)
    }

    private func healingCooldownRemainingLocked() -> TimeInterval {
        guard let lastHealingKeyDownUptime else { return 0 }
        return max(
            0,
            lastHealingGroupCooldown - (uptimeProvider() - lastHealingKeyDownUptime)
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
