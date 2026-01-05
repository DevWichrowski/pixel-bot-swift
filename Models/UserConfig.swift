import Foundation

/// Region configuration (x, y, width, height)
struct RegionConfig: Codable, Equatable {
    var hpRegion: [Int]?   // [x, y, width, height]
    var manaRegion: [Int]? // [x, y, width, height]
    
    var isHPConfigured: Bool { hpRegion != nil }
    var isManaConfigured: Bool { manaRegion != nil }
    var isFullyConfigured: Bool { isHPConfigured && isManaConfigured }
    
    /// Convert to tuple for easier use
    func hpRegionTuple() -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let r = hpRegion, r.count == 4 else { return nil }
        return (r[0], r[1], r[2], r[3])
    }
    
    func manaRegionTuple() -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let r = manaRegion, r.count == 4 else { return nil }
        return (r[0], r[1], r[2], r[3])
    }
}

/// Healer configuration
struct HealerConfig: Codable {
    var healEnabled: Bool = true
    var healThreshold: Int = 75
    var healHotkey: String = "F1"
    
    var criticalEnabled: Bool = true
    var criticalThreshold: Int = 50
    var criticalHotkey: String = "F2"
    var criticalIsPotion: Bool = false  // Share cooldown with mana
    
    var manaEnabled: Bool = true
    var manaThreshold: Int = 60
    var manaHotkey: String = "F4"
}

/// Eater configuration
struct EaterConfig: Codable {
    var enabled: Bool = false
    var foodType: String = "fire_mushroom"
    var hotkey: String = "]"
}

/// Haste configuration
struct HasteConfig: Codable {
    var enabled: Bool = false
    var hotkey: String = "x"
}

/// Skinner configuration
struct SkinnerConfig: Codable {
    var enabled: Bool = false
    var hotkey: String = "["
}

/// Combo configuration - simple timer-based combo
struct ComboConfig: Codable {
    var enabled: Bool = false
    var startStopHotkey: String = "v"
    var comboHotkey: String = "2"
    var lootOnStop: Bool = true  // Press auto loot when combo stops
    var autoLootHotkey: String = "space"
    
    // Utito Tempo settings
    var utitoTempoHotkey: String = "F9"
    var utitoTempoEnabled: Bool = false  // Use Utito Tempo before combo
    var recastUtito: Bool = false        // Re-cast Utito every 10 seconds
}

/// A named preset containing all settings
struct PresetConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var regions: RegionConfig = RegionConfig()
    var healer: HealerConfig = HealerConfig()
    var eater: EaterConfig = EaterConfig()
    var haste: HasteConfig = HasteConfig()
    var skinner: SkinnerConfig = SkinnerConfig()
    var combo: ComboConfig = ComboConfig()
    
    /// Create preset from current config
    static func fromConfig(_ config: UserConfig, name: String) -> PresetConfig {
        PresetConfig(
            name: name,
            regions: config.regions,
            healer: config.healer,
            eater: config.eater,
            haste: config.haste,
            skinner: config.skinner,
            combo: config.combo
        )
    }
}

/// Complete user configuration
struct UserConfig: Codable {
    var regions: RegionConfig = RegionConfig()
    var healer: HealerConfig = HealerConfig()
    var eater: EaterConfig = EaterConfig()
    var haste: HasteConfig = HasteConfig()
    var skinner: SkinnerConfig = SkinnerConfig()
    var combo: ComboConfig = ComboConfig()
    
    // Presets support
    var presets: [PresetConfig] = []
    var activePresetId: UUID?
    
    /// Apply preset settings to current config
    mutating func applyPreset(_ preset: PresetConfig) {
        regions = preset.regions
        healer = preset.healer
        eater = preset.eater
        haste = preset.haste
        skinner = preset.skinner
        combo = preset.combo
        activePresetId = preset.id
    }
    
    /// Update preset with current settings
    mutating func updatePreset(id: UUID) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].regions = regions
        presets[index].healer = healer
        presets[index].eater = eater
        presets[index].haste = haste
        presets[index].skinner = skinner
        presets[index].combo = combo
    }
    
    /// Get active preset
    var activePreset: PresetConfig? {
        guard let id = activePresetId else { return nil }
        return presets.first { $0.id == id }
    }
}

