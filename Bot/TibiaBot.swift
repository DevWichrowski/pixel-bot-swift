import AppKit
import Combine
import Foundation

private struct ProcessedBotFrame: @unchecked Sendable {
    let generation: UInt64
    let ammo: NumericReadout
    let ammoDecrease: Bool
    let ammoDiagnostic: RegionDiagnostic
}

enum HPFrameContinuity: Equatable {
    case first
    case continuous
    case interrupted
    case repeatedOrOlder
}

func hpFrameContinuity(previous: TimeInterval?, current: TimeInterval) -> HPFrameContinuity {
    guard let previous else { return .first }
    guard current > previous else { return .repeatedOrOlder }
    return current - previous < 0.250 ? .continuous : .interrupted
}

/// Coordinates capture, OCR, features, persisted settings, and UI state.
@MainActor
final class TibiaBot: ObservableObject {
    // MARK: - Published runtime state

    @Published private(set) var runState: BotRunState = .stopped
    @Published var errorText = ""
    @Published private(set) var hpReadout = NumericReadout()
    @Published private(set) var manaReadout = NumericReadout()
    @Published private(set) var shieldReadout = ShieldReadout()
    @Published var magicShieldEnabled = false {
        didSet { guard !isHydratingConfig else { return }; magicShield.enabled = magicShieldEnabled; magicShield.cancelPendingActions(); saveConfig() }
    }
    @Published var magicShieldHotkey = "R" {
        didSet { guard !isHydratingConfig else { return }; magicShield.hotkey = magicShieldHotkey; magicShield.cancelPendingActions(); saveConfig() }
    }
    @Published var magicShieldThreshold = "25" {
        didSet { guard !isHydratingConfig else { return }; magicShield.threshold = Int(magicShieldThreshold) ?? 25; magicShield.cancelPendingActions(); saveConfig() }
    }
    @Published var middleMouseEnabled = false {
        didSet { updateMiddleMouseMapper() }
    }
    @Published var selectedTibiaPID: Int32 = 0 {
        didSet { inputTarget.select(selectedTibiaPID); cancelPendingRuntimeActions() }
    }
    @Published private(set) var tibiaApplications: [NSRunningApplication] = []
    @Published private(set) var ammoReadout = NumericReadout()
    @Published private(set) var hpDiagnostic: RegionDiagnostic?
    @Published private(set) var manaDiagnostic: RegionDiagnostic?
    @Published private(set) var ammoDiagnostic: RegionDiagnostic?
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published var comboIsActive = false

    var isRunning: Bool {
        switch runState {
        case .starting, .running, .stale:
            return true
        case .stopped, .needsPermission, .captureFailed:
            return false
        }
    }

    var statusText: String {
        switch runState {
        case .stopped:
            return "Capture and input are stopped"
        case .needsPermission:
            return "Grant Screen Recording and Accessibility permissions"
        case .starting:
            return "Waiting for the first complete capture frame"
        case .running:
            if startEventListeners && !inputTarget.isForeground {
                return "Capture is active. Input waits for the selected Tibia application to be foreground."
            }
            return "Capture is active and OCR data is fresh"
        case .captureFailed:
            return "Screen capture stopped after an error"
        case .stale:
            return "A required OCR value has not been confirmed for 250 ms"
        }
    }

    var hpString: String { formatted(readout: hpReadout) }
    var manaString: String { formatted(readout: manaReadout) }

    // MARK: - Healing settings

    @Published var healingVocation: HealingVocation? {
        didSet { guard !isHydratingConfig else { return }; healer.vocation = healingVocation; healer.cancelPendingHealing(); saveConfig() }
    }
    @Published var healAction: HealingAction? {
        didSet { guard !isHydratingConfig else { return }; healer.heal.action = healAction; healer.cancelPendingActions(); saveConfig() }
    }
    @Published var criticalAction: HealingAction? {
        didSet { guard !isHydratingConfig else { return }; healer.criticalHeal.action = criticalAction; healer.cancelPendingActions(); saveConfig() }
    }
    @Published var healEnabled = true {
        didSet {
            guard !isHydratingConfig else { return }
            healer.toggleHeal(healEnabled)
            saveConfig()
        }
    }
    @Published var criticalEnabled = true {
        didSet {
            guard !isHydratingConfig else { return }
            healer.toggleCriticalHeal(criticalEnabled)
            saveConfig()
        }
    }
    @Published var manaEnabled = true {
        didSet {
            guard !isHydratingConfig else { return }
            healer.toggleManaRestore(manaEnabled)
            saveConfig()
        }
    }
    @Published var criticalIsPotion = false {
        didSet {
            guard !isHydratingConfig else { return }
            healer.criticalIsPotion = criticalIsPotion
            if criticalIsPotion && spiritPotionHeal {
                spiritPotionHeal = false
            }
            saveConfig()
        }
    }
    @Published var spiritPotionHeal = false {
        didSet {
            guard !isHydratingConfig else { return }
            healer.spiritPotionHeal = spiritPotionHeal
            if spiritPotionHeal && criticalIsPotion {
                criticalIsPotion = false
            }
            saveConfig()
        }
    }
    @Published var spiritPotionHotkey = "F3" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.spiritPotionHotkey = spiritPotionHotkey
            saveConfig()
        }
    }
    @Published var spiritPotionThreshold = "40" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.setSpiritPotionThreshold(Int(spiritPotionThreshold) ?? 40)
            saveConfig()
        }
    }
    @Published var healThreshold = "75" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.setHealThreshold(Int(healThreshold) ?? 75)
            saveConfig()
        }
    }
    @Published var criticalThreshold = "50" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.setCriticalThreshold(Int(criticalThreshold) ?? 50)
            saveConfig()
        }
    }
    @Published var manaThreshold = "60" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.setManaThreshold(Int(manaThreshold) ?? 60)
            saveConfig()
        }
    }
    @Published var healHotkey = "F1" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.heal.hotkey = healHotkey
            saveConfig()
        }
    }
    @Published var criticalHotkey = "F2" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.criticalHeal.hotkey = criticalHotkey
            saveConfig()
        }
    }
    @Published var manaHotkey = "F4" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.manaRestore.hotkey = manaHotkey
            saveConfig()
        }
    }
    @Published var potionCooldown = "0.5" {
        didSet {
            guard !isHydratingConfig else { return }
            healer.potionCooldown = Double(potionCooldown) ?? 0.5
            saveConfig()
        }
    }

    // MARK: - Feature settings

    @Published var eaterEnabled = false {
        didSet {
            guard !isHydratingConfig else { return }
            eater.toggle(isRunning && eaterEnabled)
            saveConfig()
        }
    }
    @Published var foodType = "fire_mushroom" {
        didSet {
            guard !isHydratingConfig else { return }
            eater.setFoodType(foodType)
            saveConfig()
        }
    }
    @Published var eaterHotkey = "]" {
        didSet {
            guard !isHydratingConfig else { return }
            eater.hotkey = eaterHotkey
            saveConfig()
        }
    }
    @Published var hasteEnabled = false {
        didSet {
            guard !isHydratingConfig else { return }
            haste.toggle(isRunning && hasteEnabled)
            saveConfig()
        }
    }
    @Published var hasteHotkey = "x" {
        didSet {
            guard !isHydratingConfig else { return }
            haste.hotkey = hasteHotkey
            saveConfig()
        }
    }
    @Published var skinnerEnabled = false {
        didSet {
            guard !isHydratingConfig else { return }
            skinner.toggle(isRunning && skinnerEnabled)
            if isRunning && skinnerEnabled && startEventListeners {
                skinner.start()
            }
            saveConfig()
        }
    }
    @Published var skinnerHotkey = "[" {
        didSet {
            guard !isHydratingConfig else { return }
            skinner.hotkey = skinnerHotkey
            saveConfig()
        }
    }
    @Published var comboEnabled = false {
        didSet {
            guard !isHydratingConfig else { return }
            combo.toggle(isRunning && comboEnabled)
            saveConfig()
        }
    }
    @Published var comboStartStopHotkey = "v" {
        didSet {
            guard !isHydratingConfig else { return }
            combo.startStopHotkey = comboStartStopHotkey
            saveConfig()
        }
    }
    @Published var comboHotkey = "2" {
        didSet {
            guard !isHydratingConfig else { return }
            combo.comboHotkey = comboHotkey
            saveConfig()
        }
    }
    @Published var lootOnStop = true {
        didSet {
            guard !isHydratingConfig else { return }
            combo.lootOnStop = lootOnStop
            saveConfig()
        }
    }
    @Published var autoLootHotkey = "space" {
        didSet {
            guard !isHydratingConfig else { return }
            combo.autoLootHotkey = autoLootHotkey
            saveConfig()
        }
    }
    @Published var utitoTempoHotkey = "F9" {
        didSet {
            guard !isHydratingConfig else { return }
            combo.utitoTempoHotkey = utitoTempoHotkey
            saveConfig()
        }
    }
    @Published var utitoTempoEnabled = false {
        didSet {
            guard !isHydratingConfig else { return }
            combo.utitoTempoEnabled = utitoTempoEnabled
            if utitoTempoEnabled && paladinComboEnabled {
                paladinComboEnabled = false
            }
            saveConfig()
        }
    }
    @Published var recastUtito = false {
        didSet {
            guard !isHydratingConfig else { return }
            combo.recastUtito = recastUtito
            saveConfig()
        }
    }
    @Published var paladinComboEnabled = false {
        didSet {
            guard !isHydratingConfig else { return }
            combo.paladinComboEnabled = paladinComboEnabled
            if paladinComboEnabled && utitoTempoEnabled {
                utitoTempoEnabled = false
            }
            saveConfig()
        }
    }

    // MARK: - Region state

    @Published private(set) var hpRegionStatus = "✗ Not set"
    @Published private(set) var manaRegionStatus = "✗ Not set"
    @Published private(set) var ammoRegionStatus = "✗ Not set"

    // MARK: - Dependencies and lifecycle

    private let configManager: ConfigManager
    private let screenCapture: ScreenCaptureService
    private let reader: HPManaReader
    private let ammoReader: AmmoReader
    private let regionSelector: RegionSelector
    private let keyPress: KeyPressService
    private let accessibilityChecker: () -> Bool
    private let startEventListeners: Bool

    private let inputTarget = TibiaInputTarget()
    private var mouseMapper: MiddleMouseKeyMapper?
    private var shutdownObserver: NSObjectProtocol?
    private var focusObserver: NSObjectProtocol?
    private var applicationObservers: [NSObjectProtocol] = []
    private var hpDecisionCounts: [Int: Int] = [:]
    private var lastDecisionTimestamp: TimeInterval?
    private var latestHP = NumericReadout()
    private var latestMana = NumericReadout()
    private var latestShield = ShieldReadout()
    private var lastUIPublish: [CaptureRegionKind: Date] = [:]
    let magicShield: AutoMagicShield
    let healer: AutoHealer
    let eater: AutoEater
    let haste: AutoHaste
    let skinner: AutoSkinner
    let combo: AutoCombo

    private var isHydratingConfig = false
    private var captureRegions = CaptureRegions()
    private var activeSession = UUID()
    private var expectedCaptureGeneration: UInt64?
    private var pipelineRevision: UInt64 = 0
    private var firstCompleteFrameAt: Date?
    private var captureLifecycleTask: Task<Void, Never>?
    private var regionUpdateTask: Task<Void, Never>?
    private var freshnessTask: Task<Void, Never>?
    private var diagnosticRefreshTask: Task<Void, Never>?
    private var lastAcceptedHPFrameTimestamp: TimeInterval?
    private var lastAcceptedManaFrameTimestamp: TimeInterval?
    private var lastHPLogAt = Date.distantPast
    private var lastLoggedHP: Int?

    init(
        configManager: ConfigManager = .shared,
        screenCapture: ScreenCaptureService = .shared,
        reader: HPManaReader = HPManaReader(diagnosticLogger: PixelBotDiagnosticLogger.shared),
        ammoReader: AmmoReader = AmmoReader(),
        regionSelector: RegionSelector? = nil,
        keyPress: KeyPressService = .shared,
        healer: AutoHealer? = nil,
        eater: AutoEater? = nil,
        haste: AutoHaste? = nil,
        skinner: AutoSkinner? = nil,
        combo: AutoCombo? = nil,
        accessibilityChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
        startEventListeners: Bool = true,
        requestPermissionsOnInit: Bool = true
    ) {
        self.configManager = configManager
        self.screenCapture = screenCapture
        self.reader = reader
        self.ammoReader = ammoReader
        self.regionSelector = regionSelector ?? .shared
        self.keyPress = keyPress
        self.magicShield = AutoMagicShield(keyPress: keyPress)
        self.healer = healer ?? AutoHealer(
            keyPress: keyPress,
            diagnosticLogger: PixelBotDiagnosticLogger.shared
        )
        self.eater = eater ?? AutoEater(keyPress: keyPress)
        self.haste = haste ?? AutoHaste(keyPress: keyPress)
        self.skinner = skinner ?? AutoSkinner(keyPress: keyPress)
        self.combo = combo ?? AutoCombo(keyPress: keyPress)
        self.accessibilityChecker = accessibilityChecker
        self.startEventListeners = startEventListeners

        self.combo.onActiveChanged = { [weak self] isActive in
            Task { @MainActor [weak self] in
                self?.comboIsActive = isActive
            }
        }

        if startEventListeners {
            let target = inputTarget
            keyPress.setInputAllowed { target.isForeground }
            self.combo.inputAllowed = { target.isForeground }
            self.combo.onListenerError = { [weak self] message in
                Task { @MainActor [weak self] in self?.errorText = message }
            }
            self.skinner.inputAllowed = { target.isForeground }
            self.skinner.onListenerError = { [weak self] message in
                Task { @MainActor [weak self] in self?.errorText = message }
            }
            mouseMapper = MiddleMouseKeyMapper(keyPress: keyPress)
            mouseMapper?.inputAllowed = { target.isForeground }
            refreshTibiaApplications()
            for name in [NSWorkspace.didLaunchApplicationNotification,
                         NSWorkspace.didTerminateApplicationNotification,
                         NSWorkspace.didActivateApplicationNotification] {
                applicationObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshTibiaApplications() }
                })
            }
            focusObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRunning, !target.isForeground else { return }
                    self.keyPress.cancelAll()
                    self.cancelPendingRuntimeActions()
                }
            }
            shutdownObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.shutdown() }
            }
        }
        refreshPermissionState(requestScreenRecording: requestPermissionsOnInit)
        loadConfig(reconfigureCapture: false)
        keyPress.cancelAll()
        pauseRuntimeFeatures()
    }

    deinit {
        if let shutdownObserver { NotificationCenter.default.removeObserver(shutdownObserver) }
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver) }
        for observer in applicationObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        captureLifecycleTask?.cancel()
        regionUpdateTask?.cancel()
        freshnessTask?.cancel()
        diagnosticRefreshTask?.cancel()
        healer.cancelPendingActions()
        eater.cancelPendingActions()
        skinner.cancelPendingActions()
        combo.cancelPendingActions()
        keyPress.cancelAll()
        combo.stopListener()
        skinner.stop()

        let capture = screenCapture
        Task { @MainActor in
            await capture.stop()
        }
    }

    func shutdown() {
        stop()
        configManager.flush()
    }

    private func updateMiddleMouseMapper() {
        mouseMapper?.enabled = isRunning && middleMouseEnabled
        if isRunning && middleMouseEnabled {
            if mouseMapper?.start() == false { errorText = "Middle mouse listener failed. Check Accessibility permission." }
        } else { mouseMapper?.stop() }
    }

    private func refreshTibiaApplications() {
        tibiaApplications = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && ($0.bundleIdentifier == "com.tibia.client"
                || ($0.bundleIdentifier == nil && $0.localizedName?.lowercased() == "tibia"))
        }
        let resolved = Self.resolveTibiaPID(selected: selectedTibiaPID,
            available: tibiaApplications.map(\.processIdentifier))
        if selectedTibiaPID != resolved { selectedTibiaPID = resolved }
        inputTarget.select(resolved)
    }

    nonisolated static func resolveTibiaPID(selected: Int32, available: [Int32]) -> Int32 {
        if available.contains(selected) { return selected }
        return available.count == 1 ? available[0] : 0
    }

    private var hasControlCollision: Bool {
        guard comboEnabled else { return false }
        let outputs = [healHotkey, criticalHotkey, manaHotkey, spiritPotionHotkey,
                       eaterHotkey, hasteHotkey, skinnerHotkey, comboHotkey,
                       autoLootHotkey, utitoTempoHotkey, magicShieldHotkey]
        return outputs.contains { $0.lowercased() == comboStartStopHotkey.lowercased() }
    }

    private func inputIsReady() -> Bool {
        guard !hasControlCollision else {
            errorText = "Combo control hotkey conflicts with an output hotkey. Choose separate keys."
            keyPress.cancelAll()
            cancelPendingRuntimeActions()
            return false
        }
        if startEventListeners && !accessibilityChecker() {
            errorText = "Accessibility permission is no longer available. Restore permission before input can resume."
        }
        guard !startEventListeners || (inputTarget.isForeground && accessibilityChecker()) else {
            keyPress.cancelAll()
            cancelPendingRuntimeActions()
            return false
        }
        keyPress.resume()
        return true
    }

    // MARK: - Configuration

    private func loadConfig(reconfigureCapture: Bool) {
        let config = configManager.config
        isHydratingConfig = true

        healingVocation = config.healer.vocation
        healAction = config.healer.healAction
        criticalAction = config.healer.criticalAction
        healEnabled = config.healer.healEnabled
        healThreshold = String(config.healer.healThreshold)
        healHotkey = config.healer.healHotkey
        criticalEnabled = config.healer.criticalEnabled
        criticalThreshold = String(config.healer.criticalThreshold)
        criticalHotkey = config.healer.criticalHotkey
        criticalIsPotion = config.healer.criticalIsPotion
        spiritPotionHeal = config.healer.spiritPotionHeal
        spiritPotionHotkey = config.healer.spiritPotionHotkey
        spiritPotionThreshold = String(config.healer.spiritPotionThreshold)
        manaEnabled = config.healer.manaEnabled
        manaThreshold = String(config.healer.manaThreshold)
        manaHotkey = config.healer.manaHotkey
        potionCooldown = String(config.healer.potionCooldown)

        eaterEnabled = config.eater.enabled
        foodType = config.eater.foodType
        eaterHotkey = config.eater.hotkey
        magicShieldEnabled = config.magicShield.enabled
        magicShieldHotkey = config.magicShield.hotkey
        magicShieldThreshold = String(config.magicShield.threshold)
        hasteEnabled = config.haste.enabled
        hasteHotkey = config.haste.hotkey
        skinnerEnabled = config.skinner.enabled
        skinnerHotkey = config.skinner.hotkey

        comboEnabled = config.combo.enabled
        comboStartStopHotkey = config.combo.startStopHotkey
        comboHotkey = config.combo.comboHotkey
        lootOnStop = config.combo.lootOnStop
        autoLootHotkey = config.combo.autoLootHotkey
        utitoTempoHotkey = config.combo.utitoTempoHotkey
        utitoTempoEnabled = config.combo.utitoTempoEnabled
        recastUtito = config.combo.recastUtito
        paladinComboEnabled = config.combo.paladinComboEnabled

        if criticalIsPotion && spiritPotionHeal {
            criticalIsPotion = false
        }
        if utitoTempoEnabled && paladinComboEnabled {
            utitoTempoEnabled = false
        }

        applyCompleteConfigurationToFeatures()
        isHydratingConfig = false
        inputTarget.setControlsValid(!hasControlCollision)

        let regions = captureRegions(from: config.regions)
        captureRegions = regions
        updateRegionStatus(using: config.regions, validRegions: regions)
        applyCaptureRegions(regions, reconfigureCapture: reconfigureCapture)
    }

    private func applyCompleteConfigurationToFeatures() {
        healer.vocation = healingVocation
        healer.heal = HealConfig(
            enabled: healEnabled,
            threshold: Int(healThreshold) ?? 75,
            hotkey: healHotkey,
            action: healAction
        )
        healer.criticalHeal = HealConfig(
            enabled: criticalEnabled,
            threshold: Int(criticalThreshold) ?? 50,
            hotkey: criticalHotkey,
            action: criticalAction
        )
        healer.manaRestore = HealConfig(
            enabled: manaEnabled,
            threshold: Int(manaThreshold) ?? 60,
            hotkey: manaHotkey
        )
        healer.criticalIsPotion = criticalIsPotion
        healer.spiritPotionHeal = spiritPotionHeal
        healer.spiritPotionHotkey = spiritPotionHotkey
        healer.spiritPotionThreshold = Int(spiritPotionThreshold) ?? 40
        healer.potionCooldown = Double(potionCooldown) ?? 0.5

        eater.setFoodType(foodType)
        eater.hotkey = eaterHotkey
        eater.toggle(isRunning && eaterEnabled)
        magicShield.enabled = magicShieldEnabled
        magicShield.hotkey = magicShieldHotkey
        magicShield.threshold = Int(magicShieldThreshold) ?? 25
        haste.hotkey = hasteHotkey
        haste.toggle(isRunning && hasteEnabled)
        skinner.hotkey = skinnerHotkey
        skinner.toggle(isRunning && skinnerEnabled)

        combo.startStopHotkey = comboStartStopHotkey
        combo.comboHotkey = comboHotkey
        combo.lootOnStop = lootOnStop
        combo.autoLootHotkey = autoLootHotkey
        combo.utitoTempoHotkey = utitoTempoHotkey
        combo.utitoTempoEnabled = utitoTempoEnabled
        combo.recastUtito = recastUtito
        combo.paladinComboEnabled = paladinComboEnabled
        combo.toggle(isRunning && comboEnabled)
    }

    private func saveConfig() {
        guard !isHydratingConfig else { return }
        cancelPendingRuntimeActions()
        hpDecisionCounts.removeAll()
        lastDecisionTimestamp = nil
        inputTarget.setControlsValid(!hasControlCollision)

        var config = configManager.config
        config.healer.vocation = healingVocation
        config.healer.healAction = healAction
        config.healer.criticalAction = criticalAction
        config.healer.healEnabled = healEnabled
        config.healer.healThreshold = Int(healThreshold) ?? 75
        config.healer.healHotkey = healHotkey
        config.healer.criticalEnabled = criticalEnabled
        config.healer.criticalThreshold = Int(criticalThreshold) ?? 50
        config.healer.criticalHotkey = criticalHotkey
        config.healer.criticalIsPotion = criticalIsPotion
        config.healer.spiritPotionHeal = spiritPotionHeal
        config.healer.spiritPotionHotkey = spiritPotionHotkey
        config.healer.spiritPotionThreshold = Int(spiritPotionThreshold) ?? 40
        config.healer.manaEnabled = manaEnabled
        config.healer.manaThreshold = Int(manaThreshold) ?? 60
        config.healer.manaHotkey = manaHotkey
        config.healer.potionCooldown = Double(potionCooldown) ?? 0.5
        config.eater.enabled = eaterEnabled
        config.eater.foodType = foodType
        config.eater.hotkey = eaterHotkey
        config.magicShield.enabled = magicShieldEnabled
        config.magicShield.hotkey = magicShieldHotkey
        config.magicShield.threshold = Int(magicShieldThreshold) ?? 25
        config.haste.enabled = hasteEnabled
        config.haste.hotkey = hasteHotkey
        config.skinner.enabled = skinnerEnabled
        config.skinner.hotkey = skinnerHotkey
        config.combo.enabled = comboEnabled
        config.combo.startStopHotkey = comboStartStopHotkey
        config.combo.comboHotkey = comboHotkey
        config.combo.lootOnStop = lootOnStop
        config.combo.autoLootHotkey = autoLootHotkey
        config.combo.utitoTempoHotkey = utitoTempoHotkey
        config.combo.utitoTempoEnabled = utitoTempoEnabled
        config.combo.recastUtito = recastUtito
        config.combo.paladinComboEnabled = paladinComboEnabled
        configManager.config = config
        configManager.save()
    }

    // MARK: - Presets

    var presets: [PresetConfig] { configManager.config.presets }
    var activePresetId: UUID? { configManager.config.activePresetId }

    @discardableResult
    func createPreset(name: String) -> UUID {
        let preset = PresetConfig.fromConfig(configManager.config, name: name)
        objectWillChange.send()
        configManager.config.presets.append(preset)
        configManager.config.activePresetId = preset.id
        configManager.save()
        return preset.id
    }

    func loadPreset(id: UUID) {
        guard let preset = configManager.config.presets.first(where: { $0.id == id }) else { return }
        invalidateCapturePipeline()
        objectWillChange.send()
        configManager.config.applyPreset(preset)
        configManager.save()
        loadConfig(reconfigureCapture: isRunning)
    }

    func saveToPreset(id: UUID) {
        objectWillChange.send()
        configManager.config.updatePreset(id: id)
        configManager.save()
    }

    func deletePreset(id: UUID) {
        objectWillChange.send()
        configManager.config.presets.removeAll { $0.id == id }
        if configManager.config.activePresetId == id {
            configManager.config.activePresetId = nil
        }
        configManager.save()
    }

    func renamePreset(id: UUID, name: String) {
        guard let index = configManager.config.presets.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        configManager.config.presets[index].name = name
        configManager.save()
    }

    func resetConfig() {
        stop()
        invalidateCapturePipeline()
        configManager.reset()
        loadConfig(reconfigureCapture: false)
    }

    // MARK: - Region selection and diagnostics

    func selectHPRegion() {
        selectRegion(kind: .hp)
    }

    func selectManaRegion() {
        selectRegion(kind: .mana)
    }

    func selectAmmoRegion() {
        selectRegion(kind: .ammo)
    }

    private func selectRegion(kind: CaptureRegionKind) {
        regionSelector.selectRegion { [weak self] tuple in
            Task { @MainActor [weak self] in
                guard let self, let tuple else { return }
                self.acceptSelectedRegion(tuple, kind: kind)
            }
        }
    }

    private func acceptSelectedRegion(
        _ tuple: (x: Int, y: Int, width: Int, height: Int),
        kind: CaptureRegionKind
    ) {
        guard let region = CaptureRegion(tuple), region.isContained(in: mainDisplaySize) else {
            errorText = "The selected region must fit completely inside the main display"
            return
        }

        switch kind {
        case .hp:
            configManager.config.regions.hpRegion = [tuple.x, tuple.y, tuple.width, tuple.height]
        case .mana:
            configManager.config.regions.manaRegion = [tuple.x, tuple.y, tuple.width, tuple.height]
        case .ammo:
            configManager.config.regions.ammoRegion = [tuple.x, tuple.y, tuple.width, tuple.height]
        }
        configManager.save()

        var regions = captureRegions
        regions[kind] = region
        captureRegions = regions
        updateRegionStatus(using: configManager.config.regions, validRegions: regions)
        errorText = ""
        applyCaptureRegions(regions, reconfigureCapture: isRunning)
    }

    func refreshDiagnostic(kind: CaptureRegionKind) {
        refreshPermissionState(requestScreenRecording: true)
        guard screenRecordingGranted else {
            errorText = "Screen Recording permission is required for the OCR test"
            return
        }
        guard let region = captureRegions[kind] else {
            errorText = "Select the \(kind.rawValue.uppercased()) region first"
            return
        }

        diagnosticRefreshTask?.cancel()
        let regions = captureRegions
        let revision = pipelineRevision
        let session = activeSession
        let wasRunning = isRunning
        diagnosticRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let frame = try await screenCapture.refreshFrame(regions: regions)
                guard !Task.isCancelled else { return }
                let result = await screenCapture.performOnProcessingQueue {
                    Self.processDiagnosticFrame(frame, region: region, kind: kind)
                }
                guard !Task.isCancelled,
                      pipelineRevision == revision,
                      captureRegions[kind] == region else {
                    return
                }
                if wasRunning {
                    guard activeSession == session,
                          frame.generation == expectedCaptureGeneration else {
                        return
                    }
                }
                applyDiagnosticResult(result, kind: kind)
                errorText = ""
            } catch {
                guard !Task.isCancelled,
                      pipelineRevision == revision,
                      captureRegions[kind] == region else {
                    return
                }
                errorText = error.localizedDescription
            }
        }
    }

    private nonisolated static func processDiagnosticFrame(
        _ frame: CapturedFrame,
        region: CaptureRegion,
        kind: CaptureRegionKind
    ) -> (NumericReadout, RegionDiagnostic, ShieldReadout?) {
        let now = Date()
        switch kind {
        case .hp, .mana:
            let reader = HPManaReader(mode: .diagnostic)
            reader.setRegions(
                hp: kind == .hp ? region : nil,
                mana: kind == .mana ? region : nil,
                generation: frame.generation
            )
            let result = reader.process(frame, now: now)
            let readout = kind == .hp ? result?.hp : result?.mana
            return (
                readout ?? NumericReadout(state: .invalid),
                reader.diagnostic(for: kind, at: now),
                kind == .mana ? result?.shield : nil
            )
        case .ammo:
            let reader = AmmoReader(mode: .diagnostic)
            reader.setRegion(region, generation: frame.generation)
            let result = reader.process(frame, now: now)
            return (
                result?.readout ?? NumericReadout(state: .invalid),
                reader.diagnostic(at: now),
                nil
            )
        }
    }

    private func applyDiagnosticResult(
        _ result: (NumericReadout, RegionDiagnostic, ShieldReadout?),
        kind: CaptureRegionKind
    ) {
        switch kind {
        case .hp:
            hpReadout = result.0
            hpDiagnostic = result.1
        case .mana:
            manaReadout = result.0
            shieldReadout = result.2 ?? ShieldReadout()
            manaDiagnostic = result.1
        case .ammo:
            ammoReadout = result.0
            ammoDiagnostic = result.1
        }
    }

    // MARK: - Capture lifecycle

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        if startEventListeners { refreshTibiaApplications() }
        refreshPermissionState(requestScreenRecording: true)

        guard screenRecordingGranted, accessibilityGranted else {
            runState = .needsPermission
            errorText = permissionErrorText
            keyPress.cancelAll()
            return
        }
        guard captureRegions.hasRequiredRegions else {
            errorText = "Set valid HP and Mana regions on the main display first"
            return
        }

        errorText = ""
        runState = .starting
        firstCompleteFrameAt = nil
        lastAcceptedHPFrameTimestamp = nil
        lastAcceptedManaFrameTimestamp = nil
        lastLoggedHP = nil
        activeSession = UUID()
        let session = activeSession
        pipelineRevision &+= 1
        let expectedGeneration = screenCapture.currentGeneration &+ 1
        expectedCaptureGeneration = expectedGeneration
        configureReaders(for: captureRegions, generation: expectedGeneration)
        clearPublishedPipelineState(for: captureRegions)
        keyPress.resume()
        resumeRuntimeFeatures()
        startFreshnessMonitor(session: session)

        let previousLifecycleTask = captureLifecycleTask
        captureLifecycleTask = Task { [weak self] in
            if let previousLifecycleTask {
                await previousLifecycleTask.value
            }
            guard let self, self.activeSession == session else { return }

            let hpManaReader = self.reader
            let ammoReader = self.ammoReader
            let frameHandler: ScreenCaptureService.FrameHandler = { [weak self] frame in
                guard let vitalResult = hpManaReader.process(
                    frame,
                    onHP: { hpStage in
                        Task { @MainActor [weak self] in
                            self?.accept(hpStage, session: session)
                        }
                    }
                ) else { return }
                let manaDiagnostic = hpManaReader.diagnostic(for: .mana)
                Task { @MainActor [weak self] in
                    self?.acceptVitals(vitalResult, diagnostic: manaDiagnostic, session: session)
                }
                let ammoResult = ammoReader.process(frame)
                let processedAt = Date()
                let processed = ProcessedBotFrame(
                    generation: frame.generation,
                    ammo: ammoResult?.readout ?? ammoReader.readout(at: processedAt),
                    ammoDecrease: ammoReader.consumeDecreaseEvent(),
                    ammoDiagnostic: ammoReader.diagnostic(at: processedAt)
                )
                Task { @MainActor [weak self] in
                    self?.accept(processed, session: session)
                }
            }
            let stateHandler: ScreenCaptureService.StateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleCaptureState(state, session: session)
                }
            }

            do {
                let actualGeneration = try await self.screenCapture.start(
                    regions: self.captureRegions,
                    frameHandler: frameHandler,
                    stateHandler: stateHandler
                )
                guard self.activeSession == session else {
                    await self.screenCapture.stop()
                    return
                }
                if actualGeneration != expectedGeneration {
                    self.configureReaders(for: self.captureRegions, generation: actualGeneration)
                    self.expectedCaptureGeneration = actualGeneration
                }
            } catch {
                guard self.activeSession == session else { return }
                self.handleCaptureFailure(error)
            }
        }
    }

    func stop() {
        captureLifecycleTask?.cancel()
        regionUpdateTask?.cancel()
        diagnosticRefreshTask?.cancel()
        activeSession = UUID()
        expectedCaptureGeneration = nil
        firstCompleteFrameAt = nil
        lastAcceptedHPFrameTimestamp = nil
        lastAcceptedManaFrameTimestamp = nil
        lastLoggedHP = nil
        freshnessTask?.cancel()
        regionUpdateTask = nil
        diagnosticRefreshTask = nil
        runState = .stopped
        PixelBotDiagnosticLogger.shared.log("runtime_metrics", fields: DiagnosticMetrics.shared.snapshot())
        errorText = ""
        keyPress.cancelAll()
        pauseRuntimeFeatures()

        captureLifecycleTask = Task { [screenCapture] in
            await screenCapture.stop()
        }
    }

    private func accept(_ frame: ProcessedBotFrame, session: UUID) {
        guard session == activeSession,
              frame.generation == expectedCaptureGeneration,
              frame.generation == screenCapture.currentGeneration,
              screenCapture.runState != .captureFailed else {
            return
        }

        let freshAmmo = refreshed(frame.ammo)
        if shouldPublish(.ammo, stateChanged: ammoReadout.state != freshAmmo.state) {
            ammoReadout = freshAmmo
            ammoDiagnostic = refreshed(frame.ammoDiagnostic, using: freshAmmo)
        }
        if firstCompleteFrameAt == nil {
            firstCompleteFrameAt = Date()
        }
        refreshRunState()
        evaluateManaAndOtherFeatures(using: frame)
    }

    private func accept(_ hpStage: HPFrameReadout, session: UUID) {
        let now = Date()
        guard session == activeSession,
              hpStage.generation == expectedCaptureGeneration,
              hpStage.generation == screenCapture.currentGeneration,
              screenCapture.runState != .captureFailed else {
            return
        }

        let readout = refreshed(hpStage.readout, at: now)
        guard let timestamp = readout.timestamp else { return }
        let frameTime = readout.captureUptime ?? timestamp.timeIntervalSinceReferenceDate
        let previousHPFrameTimestamp = lastAcceptedHPFrameTimestamp
        let continuity = hpFrameContinuity(previous: previousHPFrameTimestamp, current: frameTime)
        guard continuity != .repeatedOrOlder else { return }
        if continuity == .interrupted {
            healer.resetNormalHealingEpisode()
        }
        lastAcceptedHPFrameTimestamp = frameTime
        latestHP = readout
        if shouldPublish(.hp, stateChanged: hpReadout.state != readout.state, now: now) {
            hpReadout = readout
            hpDiagnostic = refreshed(hpStage.diagnostic, using: readout, at: now)
        }
        guard inputIsReady() else { return }
        magicShield.evaluate(hp: latestHP, mana: latestMana, shield: latestShield)
        let thresholds = Set([Int(healThreshold) ?? 75, Int(criticalThreshold) ?? 50, Int(spiritPotionThreshold) ?? 40])
        let decisionFrame = readout.captureUptime ?? timestamp.timeIntervalSinceReferenceDate
        if lastDecisionTimestamp.map({ decisionFrame > $0 }) ?? true {
            let continuous = lastDecisionTimestamp.map { decisionFrame - $0 < 0.250 } ?? false
            lastDecisionTimestamp = decisionFrame
            for threshold in thresholds {
                let below = readout.state == .valid && (readout.current ?? 0) > 0
                    && Double(readout.current ?? 0) * 100 < Double(readout.maximum ?? 0) * Double(threshold)
                hpDecisionCounts[threshold] = below ? min(2, (continuous ? hpDecisionCounts[threshold, default: 0] : 0) + 1) : 0
            }
        }

        guard readout.state == .valid, let hp = hpStage.confirmedCurrent else {
            hpDecisionCounts.removeAll()
            healer.cancelPendingHPDependentActions()
            return
        }
        if let maximum = readout.maximum {
            healer.setMaxHP(maximum)
        }
        healer.cancelInvalidHPRequests(currentHP: hp)
        if lastLoggedHP != hp && now.timeIntervalSince(lastHPLogAt) >= 0.1 {
            lastHPLogAt = now
            PixelBotDiagnosticLogger.shared.log("hp_changed", fields: [
                "frameAgeMs": .double(max(0, now.timeIntervalSince(timestamp)) * 1_000),
            ])
            lastLoggedHP = hp
        }
        evaluateHP(
            currentHP: hp,
            validFor: max(
                0,
                NumericRegionOCRPipeline.staleInterval - (readout.freshness(at: now) ?? 0.250)
            )
        )
    }

    private func shouldPublish(_ kind: CaptureRegionKind, stateChanged: Bool, now: Date = Date()) -> Bool {
        guard stateChanged || now.timeIntervalSince(lastUIPublish[kind] ?? .distantPast) >= 0.1 else { return false }
        lastUIPublish[kind] = now
        return true
    }

    private func acceptVitals(_ frame: HPManaFrameReadout, diagnostic: RegionDiagnostic, session: UUID) {
        guard session == activeSession,
              frame.generation == expectedCaptureGeneration,
              frame.generation == screenCapture.currentGeneration,
              screenCapture.runState != .captureFailed else {
            return
        }
        if let frameTime = frame.mana.captureUptime ?? frame.mana.timestamp?.timeIntervalSinceReferenceDate {
            guard lastAcceptedManaFrameTimestamp.map({ frameTime >= $0 }) ?? true else { return }
            lastAcceptedManaFrameTimestamp = frameTime
        }
        latestMana = refreshed(frame.mana)
        latestShield = frame.shield
        if shouldPublish(.mana, stateChanged: manaReadout.state != latestMana.state || shieldReadout.state != latestShield.state) {
            manaReadout = latestMana
            shieldReadout = latestShield
            manaDiagnostic = refreshed(diagnostic, using: latestMana)
        }
        guard inputIsReady() else { return }
        magicShield.evaluate(hp: latestHP, mana: latestMana, shield: latestShield)
        if latestMana.state == .valid, let mana = frame.manaConfirmedCurrent {
            if let maximum = latestMana.maximum { healer.setMaxMana(maximum) }
            healer.checkAndRestoreMana(currentMana: mana, validFor: max(0, 0.250 - (latestMana.freshness() ?? 0.250)))
        } else { healer.cancelPendingManaActions() }
    }

    private func handleCaptureState(_ state: BotRunState, session: UUID) {
        guard session == activeSession else { return }

        switch state {
        case .starting:
            runState = .starting
            firstCompleteFrameAt = nil
        case .running:
            if firstCompleteFrameAt == nil {
                firstCompleteFrameAt = Date()
            }
            runState = .running
        case .captureFailed:
            handleCaptureFailure(screenCapture.lastError ?? ScreenCaptureServiceError.captureStopped)
        case .needsPermission:
            runState = .needsPermission
            keyPress.cancelAll()
            pauseRuntimeFeatures()
        case .stopped:
            break
        case .stale:
            if runState != .stale { runState = .stale }
        }
    }

    private func handleCaptureFailure(_ error: Error) {
        runState = .captureFailed
        errorText = error.localizedDescription
        keyPress.cancelAll()
        pauseRuntimeFeatures()
        freshnessTask?.cancel()
    }

    // MARK: - Pipeline generation and freshness

    private func applyCaptureRegions(
        _ regions: CaptureRegions,
        reconfigureCapture: Bool
    ) {
        pipelineRevision &+= 1
        cancelPendingRuntimeActions()
        let revision = pipelineRevision
        expectedCaptureGeneration = nil
        clearPublishedPipelineState(for: regions)

        guard reconfigureCapture, isRunning else {
            configureReaders(for: regions, generation: screenCapture.currentGeneration)
            return
        }

        guard regions.hasRequiredRegions else {
            configureReaders(for: regions, generation: screenCapture.currentGeneration)
            stop()
            clearPublishedPipelineState(for: regions)
            errorText = "Set valid HP and Mana regions on the main display first"
            return
        }

        if runState == .starting {
            stop()
            start()
            return
        }

        runState = .starting
        firstCompleteFrameAt = nil
        let session = activeSession
        let previousUpdate = regionUpdateTask
        regionUpdateTask = Task { [weak self] in
            if let previousUpdate {
                await previousUpdate.value
            }
            guard let self,
                  self.activeSession == session,
                  self.pipelineRevision == revision else {
                return
            }

            let expectedGeneration = self.screenCapture.currentGeneration &+ 1
            self.expectedCaptureGeneration = expectedGeneration
            self.configureReaders(for: regions, generation: expectedGeneration)

            do {
                let actualGeneration = try await self.screenCapture.updateRegions(regions)
                guard self.activeSession == session, self.pipelineRevision == revision else { return }
                if actualGeneration != expectedGeneration {
                    self.configureReaders(for: regions, generation: actualGeneration)
                    self.expectedCaptureGeneration = actualGeneration
                }
            } catch {
                guard self.activeSession == session, self.pipelineRevision == revision else { return }
                self.handleCaptureFailure(error)
            }
        }
    }

    private func invalidateCapturePipeline() {
        pipelineRevision &+= 1
        cancelPendingRuntimeActions()
        expectedCaptureGeneration = nil
        reader.reset(generation: UInt64.max)
        ammoReader.reset(generation: UInt64.max)
        clearPublishedPipelineState(for: captureRegions)
    }

    private func configureReaders(for regions: CaptureRegions, generation: UInt64) {
        reader.setRegions(hp: regions.hp, mana: regions.mana, generation: generation)
        ammoReader.setRegion(regions.ammo, generation: generation)
    }

    private func clearPublishedPipelineState(for regions: CaptureRegions) {
        latestHP = NumericReadout()
        latestMana = NumericReadout()
        latestShield = ShieldReadout()
        shieldReadout = ShieldReadout()
        hpDecisionCounts.removeAll()
        lastDecisionTimestamp = nil
        hpReadout = NumericReadout(state: regions.hp == nil ? .unconfigured : .invalid)
        manaReadout = NumericReadout(state: regions.mana == nil ? .unconfigured : .invalid)
        ammoReadout = NumericReadout(state: regions.ammo == nil ? .unconfigured : .invalid)
        hpDiagnostic = regions.hp == nil ? nil : RegionDiagnostic(state: .invalid)
        manaDiagnostic = regions.mana == nil ? nil : RegionDiagnostic(state: .invalid)
        ammoDiagnostic = regions.ammo == nil ? nil : RegionDiagnostic(state: .invalid)
    }

    private func startFreshnessMonitor(session: UUID) {
        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.activeSession == session, self.isRunning else { return }
                if self.inputIsReady() {
                    self.magicShield.evaluate(hp: self.latestHP, mana: self.latestMana, shield: self.latestShield)
                }
                self.refreshPublishedFreshness()
            }
        }
    }

    private func refreshPublishedFreshness() {
        let hpState = latestHP.state(at: Date())
        let manaState = latestMana.state(at: Date())
        let ammoState = ammoReadout.state(at: Date())
        if hpReadout.state != hpState {
            hpReadout = refreshed(latestHP)
            if let diagnostic = hpDiagnostic { hpDiagnostic = refreshed(diagnostic, using: hpReadout) }
        }
        if manaReadout.state != manaState {
            manaReadout = refreshed(latestMana)
            if let diagnostic = manaDiagnostic { manaDiagnostic = refreshed(diagnostic, using: manaReadout) }
        }
        if ammoReadout.state != ammoState {
            ammoReadout = refreshed(ammoReadout)
            if let diagnostic = ammoDiagnostic { ammoDiagnostic = refreshed(diagnostic, using: ammoReadout) }
        }
        let shieldState = latestShield.state(at: Date())
        if shieldReadout.state != shieldState { shieldReadout.state = shieldState }
        if latestMana.state(at: Date()) != .valid { healer.cancelPendingManaActions() }
        if hpReadout.state != .valid {
            healer.cancelPendingHPDependentActions()
        }
        refreshRunState()
    }

    private func refreshed(_ readout: NumericReadout, at date: Date = Date()) -> NumericReadout {
        var result = readout
        result.state = readout.state(at: date, staleAfter: NumericRegionOCRPipeline.staleInterval)
        return result
    }

    private func refreshed(
        _ diagnostic: RegionDiagnostic,
        using readout: NumericReadout,
        at date: Date = Date()
    ) -> RegionDiagnostic {
        var result = diagnostic
        result.freshness = readout.freshness(at: date)
        if result.state != .unconfigured {
            result.state = readout.state
        }
        return result
    }

    private func refreshRunState(at date: Date = Date()) {
        guard isRunning, screenCapture.runState != .captureFailed else { return }
        let requiredAreValid = latestHP.state(at: date) == .valid && latestMana.state(at: date) == .valid
        if requiredAreValid {
            if runState != .running { runState = .running }
            return
        }

        if let firstCompleteFrameAt,
           date.timeIntervalSince(firstCompleteFrameAt) >= NumericRegionOCRPipeline.staleInterval {
            if runState != .stale { runState = .stale }
        }
    }

    // MARK: - Feature evaluation

    private func evaluateHP(currentHP: Int, validFor: TimeInterval) {
        let normalConfirmed = hpDecisionCounts[Int(healThreshold) ?? 75, default: 0] >= 2
        let criticalConfirmed = hpDecisionCounts[Int(criticalThreshold) ?? 50, default: 0] >= 2
        let spiritConfirmed = hpDecisionCounts[Int(spiritPotionThreshold) ?? 40, default: 0] >= 2
        evaluateHP(
            currentHP: currentHP,
            validFor: validFor,
            normalConfirmed: normalConfirmed,
            criticalConfirmed: criticalConfirmed,
            spiritConfirmed: spiritConfirmed
        )
    }

    /// Internal seam for verifying the production healing-mode routing.
    func evaluateHP(
        currentHP: Int,
        validFor: TimeInterval,
        normalConfirmed: Bool,
        criticalConfirmed: Bool,
        spiritConfirmed: Bool
    ) {
        if spiritPotionHeal {
            _ = healer.checkSpiritPotionHeal(currentHP: currentHP, validFor: validFor,
                                            allowCritical: criticalConfirmed,
                                            allowNormal: normalConfirmed,
                                            allowPotion: spiritConfirmed)
        } else if criticalIsPotion {
            if criticalConfirmed { _ = healer.checkCriticalPotionHeal(currentHP: currentHP, validFor: validFor) }
            if normalConfirmed { healer.checkNormalHealOnly(currentHP: currentHP, validFor: validFor) }
        } else if criticalConfirmed {
            healer.checkAndHeal(currentHP: currentHP, validFor: validFor, allowNormal: normalConfirmed)
        } else if normalConfirmed {
            healer.checkNormalHealOnly(currentHP: currentHP, validFor: validFor)
        }
    }

    private func evaluateManaAndOtherFeatures(using frame: ProcessedBotFrame) {
        guard inputIsReady() else { return }
        let ammoIsValid = frame.ammo.state(at: Date()) == .valid

        let nonCriticalActions: [() -> Void] = [
            { [weak self] in self?.eater.checkAndEat() },
            { [weak self] in self?.haste.checkAndCast() },
            { [weak self] in
                guard let self else { return }
                self.combo.checkAndPress()
                self.combo.checkPaladinCombo(
                    ammoDecreased: ammoIsValid && frame.ammoDecrease,
                    validFor: max(0, 0.250 - (frame.ammo.freshness() ?? 0.250))
                )
            },
        ]
        let actions = Double.random(in: 0...1) < 0.2 ? nonCriticalActions.shuffled() : nonCriticalActions
        actions.forEach { $0() }
    }

    // MARK: - Runtime features and permissions

    private func resumeRuntimeFeatures() {
        updateMiddleMouseMapper()
        eater.toggle(eaterEnabled)
        haste.toggle(hasteEnabled)
        skinner.toggle(skinnerEnabled)
        if skinnerEnabled && startEventListeners {
            skinner.start()
        }
        combo.toggle(comboEnabled)
    }

    private func pauseRuntimeFeatures() {
        mouseMapper?.enabled = false
        mouseMapper?.stop()
        magicShield.cancelPendingActions()
        healer.cancelPendingActions()
        eater.toggle(false)
        haste.toggle(false)
        skinner.toggle(false)
        combo.toggle(false)
        comboIsActive = false
    }

    private func cancelPendingRuntimeActions() {
        magicShield.cancelPendingActions()
        healer.cancelPendingActions()
        eater.cancelPendingActions()
        haste.cancelPendingActions()
        skinner.cancelPendingActions()
        combo.cancelPendingActions()
    }

    private func refreshPermissionState(requestScreenRecording: Bool) {
        screenRecordingGranted = screenCapture.checkPermission(requestIfNeeded: requestScreenRecording)
        accessibilityGranted = accessibilityChecker()
    }

    private var permissionErrorText: String {
        switch (screenRecordingGranted, accessibilityGranted) {
        case (false, false):
            return "Screen Recording and Accessibility permissions are required"
        case (false, true):
            return "Screen Recording permission is required"
        case (true, false):
            return "Accessibility permission is required"
        case (true, true):
            return ""
        }
    }

    // MARK: - Region helpers

    private var mainDisplaySize: CGSize {
        CGDisplayBounds(CGMainDisplayID()).size
    }

    private func captureRegions(from config: RegionConfig) -> CaptureRegions {
        CaptureRegions(
            hp: validated(config.hpRegionTuple()),
            mana: validated(config.manaRegionTuple()),
            ammo: validated(config.ammoRegionTuple())
        )
    }

    private func validated(
        _ tuple: (x: Int, y: Int, width: Int, height: Int)?
    ) -> CaptureRegion? {
        guard let tuple,
              let region = CaptureRegion(tuple),
              region.isContained(in: mainDisplaySize) else {
            return nil
        }
        return region
    }

    private func updateRegionStatus(using config: RegionConfig, validRegions: CaptureRegions) {
        hpRegionStatus = regionStatus(stored: config.hpRegion, valid: validRegions.hp)
        manaRegionStatus = regionStatus(stored: config.manaRegion, valid: validRegions.mana)
        ammoRegionStatus = regionStatus(stored: config.ammoRegion, valid: validRegions.ammo)
    }

    private func regionStatus(stored: [Int]?, valid: CaptureRegion?) -> String {
        guard stored != nil else { return "✗ Not set" }
        guard let valid else { return "✗ Invalid or outside main display" }
        let tuple = valid.integerTuple
        return "✓ \(tuple.width)×\(tuple.height) pt"
    }

    private func formatted(readout: NumericReadout) -> String {
        guard let current = readout.current, let maximum = readout.maximum else {
            return "---/---"
        }
        return "\(current)/\(maximum)"
    }
}

/// The selected process is checked again by the input queue immediately before key-down.
private final class TibiaInputTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: Int32 = 0
    private var controlsValid = true
    func setControlsValid(_ value: Bool) { lock.withLock { controlsValid = value } }
    func select(_ value: Int32) { lock.withLock { pid = value } }
    var isForeground: Bool {
        let selected = lock.withLock { controlsValid ? pid : 0 }
        return selected > 0 && NSWorkspace.shared.frontmostApplication?.processIdentifier == selected
    }
}
