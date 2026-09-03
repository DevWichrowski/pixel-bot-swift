import AppKit
import Combine
import Foundation

private struct ProcessedBotFrame: @unchecked Sendable {
    let generation: UInt64
    let mana: NumericReadout
    let ammo: NumericReadout
    let manaConfirmedCurrent: Int?
    let ammoDecrease: Bool
    let manaDiagnostic: RegionDiagnostic
    let ammoDiagnostic: RegionDiagnostic
}

/// Coordinates capture, OCR, features, persisted settings, and UI state.
@MainActor
final class TibiaBot: ObservableObject {
    // MARK: - Published runtime state

    @Published private(set) var runState: BotRunState = .stopped
    @Published var errorText = ""
    @Published private(set) var hpReadout = NumericReadout()
    @Published private(set) var manaReadout = NumericReadout()
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
    let healingGroupCooldownText = "1.0"
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
    private var lastAcceptedHPFrameTimestamp: Date?
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

        refreshPermissionState(requestScreenRecording: requestPermissionsOnInit)
        loadConfig(reconfigureCapture: false)
        keyPress.cancelAll()
        pauseRuntimeFeatures()
    }

    deinit {
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

    // MARK: - Configuration

    private func loadConfig(reconfigureCapture: Bool) {
        let config = configManager.config
        isHydratingConfig = true

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

        let regions = captureRegions(from: config.regions)
        captureRegions = regions
        updateRegionStatus(using: config.regions, validRegions: regions)
        applyCaptureRegions(regions, reconfigureCapture: reconfigureCapture)
    }

    private func applyCompleteConfigurationToFeatures() {
        healer.heal = HealConfig(
            enabled: healEnabled,
            threshold: Int(healThreshold) ?? 75,
            hotkey: healHotkey
        )
        healer.criticalHeal = HealConfig(
            enabled: criticalEnabled,
            threshold: Int(criticalThreshold) ?? 50,
            hotkey: criticalHotkey
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

        var config = configManager.config
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
        config.healer.spellCooldown = AutoHealer.healingGroupCooldown
        config.healer.potionCooldown = Double(potionCooldown) ?? 0.5
        config.eater.enabled = eaterEnabled
        config.eater.foodType = foodType
        config.eater.hotkey = eaterHotkey
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
    ) -> (NumericReadout, RegionDiagnostic) {
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
                reader.diagnostic(for: kind, at: now)
            )
        case .ammo:
            let reader = AmmoReader(mode: .diagnostic)
            reader.setRegion(region, generation: frame.generation)
            let result = reader.process(frame, now: now)
            return (
                result?.readout ?? NumericReadout(state: .invalid),
                reader.diagnostic(at: now)
            )
        }
    }

    private func applyDiagnosticResult(
        _ result: (NumericReadout, RegionDiagnostic),
        kind: CaptureRegionKind
    ) {
        switch kind {
        case .hp:
            hpReadout = result.0
            hpDiagnostic = result.1
        case .mana:
            manaReadout = result.0
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
                let ammoResult = ammoReader.process(frame)
                let processedAt = Date()
                let processed = ProcessedBotFrame(
                    generation: frame.generation,
                    mana: vitalResult.mana,
                    ammo: ammoResult?.readout ?? ammoReader.readout(at: processedAt),
                    manaConfirmedCurrent: vitalResult.manaConfirmedCurrent,
                    ammoDecrease: ammoReader.consumeDecreaseEvent(),
                    manaDiagnostic: hpManaReader.diagnostic(for: .mana, at: processedAt),
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
        lastLoggedHP = nil
        freshnessTask?.cancel()
        regionUpdateTask = nil
        diagnosticRefreshTask = nil
        runState = .stopped
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

        manaReadout = refreshed(frame.mana)
        ammoReadout = refreshed(frame.ammo)
        manaDiagnostic = refreshed(frame.manaDiagnostic, using: manaReadout)
        ammoDiagnostic = refreshed(frame.ammoDiagnostic, using: ammoReadout)
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
        guard let timestamp = readout.timestamp,
              lastAcceptedHPFrameTimestamp.map({ timestamp >= $0 }) ?? true else {
            return
        }
        lastAcceptedHPFrameTimestamp = timestamp
        hpReadout = readout
        hpDiagnostic = refreshed(hpStage.diagnostic, using: readout, at: now)

        guard readout.state == .valid, let hp = hpStage.confirmedCurrent else {
            healer.cancelPendingHPDependentActions()
            return
        }
        if let maximum = readout.maximum {
            healer.setMaxHP(maximum)
        }
        if lastLoggedHP != hp {
            PixelBotDiagnosticLogger.shared.log("hp_changed", fields: [
                "frameAgeMs": .double(max(0, now.timeIntervalSince(timestamp)) * 1_000),
            ])
            lastLoggedHP = hp
        }
        evaluateHP(
            currentHP: hp,
            validFor: max(
                0,
                NumericRegionOCRPipeline.staleInterval - now.timeIntervalSince(timestamp)
            )
        )
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
            runState = .stale
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
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, self.activeSession == session, self.isRunning else { return }
                self.refreshPublishedFreshness()
            }
        }
    }

    private func refreshPublishedFreshness() {
        hpReadout = refreshed(hpReadout)
        manaReadout = refreshed(manaReadout)
        ammoReadout = refreshed(ammoReadout)
        if let diagnostic = hpDiagnostic {
            hpDiagnostic = refreshed(diagnostic, using: hpReadout)
        }
        if let diagnostic = manaDiagnostic {
            manaDiagnostic = refreshed(diagnostic, using: manaReadout)
        }
        if let diagnostic = ammoDiagnostic {
            ammoDiagnostic = refreshed(diagnostic, using: ammoReadout)
        }
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
        let requiredAreValid = hpReadout.state == .valid && manaReadout.state == .valid
        if requiredAreValid {
            runState = .running
            return
        }

        if let firstCompleteFrameAt,
           date.timeIntervalSince(firstCompleteFrameAt) >= NumericRegionOCRPipeline.staleInterval {
            runState = .stale
        }
    }

    // MARK: - Feature evaluation

    private func evaluateHP(currentHP: Int, validFor: TimeInterval) {
        if spiritPotionHeal {
            _ = healer.checkSpiritPotionHeal(currentHP: currentHP, validFor: validFor)
            healer.checkNormalHealOnly(currentHP: currentHP, validFor: validFor)
        } else if criticalIsPotion {
            _ = healer.checkCriticalPotionHeal(currentHP: currentHP, validFor: validFor)
            healer.checkNormalHealOnly(currentHP: currentHP, validFor: validFor)
        } else {
            healer.checkAndHeal(currentHP: currentHP, validFor: validFor)
        }
    }

    private func evaluateManaAndOtherFeatures(using frame: ProcessedBotFrame) {
        let now = Date()
        let manaIsValid = frame.mana.state(at: now) == .valid
        let ammoIsValid = frame.ammo.state(at: now) == .valid
        let mana = manaIsValid ? frame.manaConfirmedCurrent : nil

        if manaIsValid, let maximum = frame.mana.maximum {
            healer.setMaxMana(maximum)
        }

        if let mana {
            healer.checkAndRestoreMana(currentMana: mana)
        }

        let nonCriticalActions: [() -> Void] = [
            { [weak self] in self?.eater.checkAndEat() },
            { [weak self] in self?.haste.checkAndCast() },
            { [weak self] in
                guard let self else { return }
                self.combo.checkAndPress()
                self.combo.checkPaladinCombo(
                    ammoDecreased: ammoIsValid && frame.ammoDecrease
                )
            },
        ]
        let actions = Double.random(in: 0...1) < 0.2 ? nonCriticalActions.shuffled() : nonCriticalActions
        actions.forEach { $0() }
    }

    // MARK: - Runtime features and permissions

    private func resumeRuntimeFeatures() {
        eater.toggle(eaterEnabled)
        haste.toggle(hasteEnabled)
        skinner.toggle(skinnerEnabled)
        if skinnerEnabled && startEventListeners {
            skinner.start()
        }
        combo.toggle(comboEnabled)
    }

    private func pauseRuntimeFeatures() {
        healer.cancelPendingActions()
        eater.toggle(false)
        haste.toggle(false)
        skinner.toggle(false)
        combo.toggle(false)
        comboIsActive = false
    }

    private func cancelPendingRuntimeActions() {
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
