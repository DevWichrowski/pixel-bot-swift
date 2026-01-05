import Foundation
import Combine
import AppKit

/// Main bot class orchestrating all features
class TibiaBot: ObservableObject {
    // MARK: - Published Properties (UI Bindings)
    
    @Published var isRunning = false
    @Published var statusText = "Ready"
    @Published var errorText = ""
    @Published var hpString = "---/---"
    @Published var manaString = "---/---"
    
    // Heal settings
    @Published var healEnabled = true { didSet { healer.toggleHeal(healEnabled); saveConfig() } }
    @Published var criticalEnabled = true { didSet { healer.toggleCriticalHeal(criticalEnabled); saveConfig() } }
    @Published var manaEnabled = true { didSet { healer.toggleManaRestore(manaEnabled); saveConfig() } }
    @Published var criticalIsPotion = false { didSet { healer.criticalIsPotion = criticalIsPotion; saveConfig() } }
    
    @Published var healThreshold = "75" { didSet { healer.setHealThreshold(Int(healThreshold) ?? 75); saveConfig() } }
    @Published var criticalThreshold = "50" { didSet { healer.setCriticalThreshold(Int(criticalThreshold) ?? 50); saveConfig() } }
    @Published var manaThreshold = "60" { didSet { healer.setManaThreshold(Int(manaThreshold) ?? 60); saveConfig() } }
    
    @Published var healHotkey = "F1" { didSet { healer.heal.hotkey = healHotkey; saveConfig() } }
    @Published var criticalHotkey = "F2" { didSet { healer.criticalHeal.hotkey = criticalHotkey; saveConfig() } }
    @Published var manaHotkey = "F4" { didSet { healer.manaRestore.hotkey = manaHotkey; saveConfig() } }
    
    // Eater settings
    @Published var eaterEnabled = false { didSet { eater.toggle(eaterEnabled); saveConfig() } }
    @Published var foodType = "fire_mushroom" { didSet { eater.setFoodType(foodType); saveConfig() } }
    @Published var eaterHotkey = "]" { didSet { eater.hotkey = eaterHotkey; saveConfig() } }
    
    // Haste settings
    @Published var hasteEnabled = false { didSet { haste.toggle(hasteEnabled); saveConfig() } }
    @Published var hasteHotkey = "x" { didSet { haste.hotkey = hasteHotkey; saveConfig() } }
    
    // Skinner settings
    @Published var skinnerEnabled = false { didSet { skinner.toggle(skinnerEnabled); saveConfig() } }
    @Published var skinnerHotkey = "[" { didSet { skinner.hotkey = skinnerHotkey; saveConfig() } }
    
    // Combo settings
    @Published var comboEnabled = false { didSet { combo.toggle(comboEnabled); saveConfig() } }
    @Published var comboIsActive = false
    @Published var comboStartStopHotkey = "v" { didSet { combo.startStopHotkey = comboStartStopHotkey; saveConfig() } }
    @Published var comboHotkey = "2" { didSet { combo.comboHotkey = comboHotkey; saveConfig() } }
    @Published var lootOnStop = true { didSet { combo.lootOnStop = lootOnStop; saveConfig() } }
    @Published var autoLootHotkey = "space" { didSet { combo.autoLootHotkey = autoLootHotkey; saveConfig() } }
    
    // Utito Tempo settings
    @Published var utitoTempoHotkey = "F9" { didSet { combo.utitoTempoHotkey = utitoTempoHotkey; saveConfig() } }
    @Published var utitoTempoEnabled = false { didSet { combo.utitoTempoEnabled = utitoTempoEnabled; saveConfig() } }
    @Published var recastUtito = false { didSet { combo.recastUtito = recastUtito; saveConfig() } }
    
    // Region status
    @Published var hpRegionStatus = "✗ Not set"
    @Published var manaRegionStatus = "✗ Not set"
    
    // MARK: - Services and Features
    
    private let configManager = ConfigManager.shared
    private let screenCapture = ScreenCaptureService.shared
    private let reader = HPManaReader()
    private let regionSelector = RegionSelector.shared
    
    let healer = AutoHealer()
    let eater = AutoEater()
    let haste = AutoHaste()
    let skinner = AutoSkinner()
    let combo = AutoCombo()
    
    private var loopTimer: Timer?
    private let refreshRate: TimeInterval = 0.1  // 100ms
    
    // MARK: - Init
    
    init() {
        loadConfig()
        skinner.start()  // Start mouse listener
        
        // Setup combo callback
        combo.onActiveChanged = { [weak self] isActive in
            DispatchQueue.main.async { self?.comboIsActive = isActive }
        }
        
        // Check permissions
        if !screenCapture.checkPermission() {
            errorText = "Need Screen Recording permission"
        }
    }
    
    deinit {
        stop()
        skinner.stop()
    }
    
    // MARK: - Config Management
    
    private func loadConfig() {
        let config = configManager.config
        
        // Healer
        healEnabled = config.healer.healEnabled
        healThreshold = String(config.healer.healThreshold)
        healHotkey = config.healer.healHotkey
        
        criticalEnabled = config.healer.criticalEnabled
        criticalThreshold = String(config.healer.criticalThreshold)
        criticalHotkey = config.healer.criticalHotkey
        criticalIsPotion = config.healer.criticalIsPotion
        
        manaEnabled = config.healer.manaEnabled
        manaThreshold = String(config.healer.manaThreshold)
        manaHotkey = config.healer.manaHotkey
        
        // Eater
        eaterEnabled = config.eater.enabled
        foodType = config.eater.foodType
        eaterHotkey = config.eater.hotkey
        
        // Haste
        hasteEnabled = config.haste.enabled
        hasteHotkey = config.haste.hotkey
        
        // Skinner
        skinnerEnabled = config.skinner.enabled
        skinnerHotkey = config.skinner.hotkey
        
        // Regions
        if let hp = config.regions.hpRegionTuple() {
            reader.hpRegion = hp
            hpRegionStatus = "✓ \(hp.width)x\(hp.height)"
        }
        
        if let mana = config.regions.manaRegionTuple() {
            reader.manaRegion = mana
            manaRegionStatus = "✓ \(mana.width)x\(mana.height)"
        }
        
        // Apply to features
        healer.heal = HealConfig(enabled: healEnabled, threshold: Int(healThreshold) ?? 75, hotkey: healHotkey)
        healer.criticalHeal = HealConfig(enabled: criticalEnabled, threshold: Int(criticalThreshold) ?? 50, hotkey: criticalHotkey)
        healer.manaRestore = HealConfig(enabled: manaEnabled, threshold: Int(manaThreshold) ?? 60, hotkey: manaHotkey)
        healer.criticalIsPotion = criticalIsPotion
        
        eater.setFoodType(foodType)
        eater.hotkey = eaterHotkey
        
        haste.hotkey = hasteHotkey
        
        skinner.hotkey = skinnerHotkey
        
        // Combo
        comboEnabled = config.combo.enabled
        comboStartStopHotkey = config.combo.startStopHotkey
        comboHotkey = config.combo.comboHotkey
        lootOnStop = config.combo.lootOnStop
        autoLootHotkey = config.combo.autoLootHotkey
        utitoTempoHotkey = config.combo.utitoTempoHotkey
        utitoTempoEnabled = config.combo.utitoTempoEnabled
        recastUtito = config.combo.recastUtito
        combo.comboHotkey = comboHotkey
        combo.startStopHotkey = comboStartStopHotkey
        combo.lootOnStop = lootOnStop
        combo.autoLootHotkey = autoLootHotkey
        combo.utitoTempoHotkey = utitoTempoHotkey
        combo.utitoTempoEnabled = utitoTempoEnabled
        combo.recastUtito = recastUtito
    }
    
    private func saveConfig() {
        var config = configManager.config
        
        config.healer.healEnabled = healEnabled
        config.healer.healThreshold = Int(healThreshold) ?? 75
        config.healer.healHotkey = healHotkey
        
        config.healer.criticalEnabled = criticalEnabled
        config.healer.criticalThreshold = Int(criticalThreshold) ?? 50
        config.healer.criticalHotkey = criticalHotkey
        config.healer.criticalIsPotion = criticalIsPotion
        
        config.healer.manaEnabled = manaEnabled
        config.healer.manaThreshold = Int(manaThreshold) ?? 60
        config.healer.manaHotkey = manaHotkey
        
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
        
        configManager.config = config
        configManager.save()
    }
    
    // MARK: - Presets Management
    
    /// Get all presets
    var presets: [PresetConfig] {
        configManager.config.presets
    }
    
    /// Get active preset ID
    var activePresetId: UUID? {
        configManager.config.activePresetId
    }
    
    /// Create new preset with current settings
    @discardableResult
    func createPreset(name: String) -> UUID {
        let preset = PresetConfig.fromConfig(configManager.config, name: name)
        configManager.config.presets.append(preset)
        configManager.config.activePresetId = preset.id
        configManager.save()
        print("📦 Created preset: \(name)")
        return preset.id
    }
    
    /// Load preset settings
    func loadPreset(id: UUID) {
        guard let preset = configManager.config.presets.first(where: { $0.id == id }) else { return }
        
        configManager.config.applyPreset(preset)
        configManager.save()
        loadConfig()
        print("📦 Loaded preset: \(preset.name)")
    }
    
    /// Save current settings to preset
    func saveToPreset(id: UUID) {
        configManager.config.updatePreset(id: id)
        configManager.save()
        
        if let preset = configManager.config.presets.first(where: { $0.id == id }) {
            print("📦 Saved to preset: \(preset.name)")
        }
    }
    
    /// Delete preset
    func deletePreset(id: UUID) {
        configManager.config.presets.removeAll { $0.id == id }
        if configManager.config.activePresetId == id {
            configManager.config.activePresetId = nil
        }
        configManager.save()
        print("📦 Deleted preset")
    }
    
    /// Rename preset
    func renamePreset(id: UUID, name: String) {
        guard let index = configManager.config.presets.firstIndex(where: { $0.id == id }) else { return }
        configManager.config.presets[index].name = name
        configManager.save()
        print("📦 Renamed preset to: \(name)")
    }
    
    func resetConfig() {
        configManager.reset()
        reader.hpRegion = nil
        reader.manaRegion = nil
        hpRegionStatus = "✗ Not set"
        manaRegionStatus = "✗ Not set"
        loadConfig()
    }
    
    // MARK: - Region Selection
    
    func selectHPRegion() {
        regionSelector.selectRegion { [weak self] region in
            guard let self = self, let region = region else { return }
            
            self.reader.hpRegion = region
            self.configManager.setHPRegion(region)
            
            DispatchQueue.main.async {
                self.hpRegionStatus = "✓ \(region.width)x\(region.height)"
            }
        }
    }
    
    func selectManaRegion() {
        regionSelector.selectRegion { [weak self] region in
            guard let self = self, let region = region else { return }
            
            self.reader.manaRegion = region
            self.configManager.setManaRegion(region)
            
            DispatchQueue.main.async {
                self.manaRegionStatus = "✓ \(region.width)x\(region.height)"
            }
        }
    }
    
    // MARK: - Bot Control
    
    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }
    
    func start() {
        guard !isRunning else { return }
        
        // Check if regions configured
        guard reader.isConfigured else {
            errorText = "Set HP and Mana regions first!"
            return
        }
        
        errorText = ""
        isRunning = true
        statusText = "Running"
        
        // Start main loop
        loopTimer = Timer.scheduledTimer(withTimeInterval: refreshRate, repeats: true) { [weak self] _ in
            self?.runLoop()
        }
        
        print("🤖 Bot started")
    }
    
    func stop() {
        isRunning = false
        statusText = "Stopped"
        loopTimer?.invalidate()
        loopTimer = nil
        print("🤖 Bot stopped")
    }
    
    // MARK: - Main Loop
    
    private func runLoop() {
        // Capture screen
        guard let screenshot = screenCapture.captureScreen() else {
            return
        }
        
        // Read HP/Mana
        let status = reader.readStatus(from: screenshot)
        
        // Update UI
        DispatchQueue.main.async { [weak self] in
            self?.hpString = status.hpString
            self?.manaString = status.manaString
        }
        
        // Set max HP/Mana from OCR (more accurate than auto-detection)
        if let maxHP = status.hpMax {
            healer.setMaxHP(maxHP)
        }
        if let maxMana = status.manaMax {
            healer.setMaxMana(maxMana)
        }
        
        // Process healing
        if criticalIsPotion {
            // Special mode: critical and mana share cooldown
            // Critical heal is handled here with priority over mana
            if let hp = status.hpCurrent, let mana = status.manaCurrent {
                _ = healer.checkCriticalAndManaWithPriority(currentHP: hp, currentMana: mana)
            }
            
            // Normal heal is independent (skip critical check - already handled above)
            if let hp = status.hpCurrent {
                healer.checkNormalHealOnly(currentHP: hp)
            }
        } else {
            // Standard mode
            if let hp = status.hpCurrent {
                healer.checkAndHeal(currentHP: hp)
            }
            
            if let mana = status.manaCurrent {
                healer.checkAndRestoreMana(currentMana: mana)
            }
        }
        
        // Process other features
        eater.checkAndEat()
        haste.checkAndCast()
        
        // Process combo (simple timer-based)
        combo.checkAndPress()
    }
}
