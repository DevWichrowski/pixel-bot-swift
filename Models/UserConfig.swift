import Foundation

/// Region configuration (x, y, width, height)
struct RegionConfig: Codable, Equatable {
    var hpRegion: [Int]?   // [x, y, width, height]
    var manaRegion: [Int]? // [x, y, width, height]
    var ammoRegion: [Int]? // [x, y, width, height] - for Paladin Combo
    
    var isHPConfigured: Bool { hpRegion != nil }
    var isManaConfigured: Bool { manaRegion != nil }
    var isAmmoConfigured: Bool { ammoRegion != nil }
    var isFullyConfigured: Bool { isHPConfigured && isManaConfigured }

    private enum CodingKeys: String, CodingKey {
        case hpRegion
        case manaRegion
        case ammoRegion
    }
    
    func hpRegionTuple() -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let r = hpRegion, r.count == 4 else { return nil }
        return (r[0], r[1], r[2], r[3])
    }
    
    func manaRegionTuple() -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let r = manaRegion, r.count == 4 else { return nil }
        return (r[0], r[1], r[2], r[3])
    }
    
    func ammoRegionTuple() -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let r = ammoRegion, r.count == 4 else { return nil }
        return (r[0], r[1], r[2], r[3])
    }
}

extension RegionConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hpRegion = try container.decodeIfPresent([Int].self, forKey: .hpRegion)
        manaRegion = try container.decodeIfPresent([Int].self, forKey: .manaRegion)
        ammoRegion = try container.decodeIfPresent([Int].self, forKey: .ammoRegion)
    }
}

/// Healer configuration
struct HealerConfig: Codable {
    var vocation: HealingVocation?
    var healAction: HealingAction?
    var criticalAction: HealingAction?
    var healEnabled: Bool = true
    var healThreshold: Int = 75
    var healHotkey: String = "F1"
    
    var criticalEnabled: Bool = true
    var criticalThreshold: Int = 50
    var criticalHotkey: String = "F2"
    var criticalIsPotion: Bool = false  // Share cooldown with mana
    var spiritPotionHeal: Bool = false   // Use Critical Spell + Spirit Potion combo
    var spiritPotionHotkey: String = "F3"
    var spiritPotionThreshold: Int = 40  // Separate threshold for Spirit Potion (decorrelated from critical)
    
    var manaEnabled: Bool = true
    var manaThreshold: Int = 60
    var manaHotkey: String = "F4"
    
    // Cooldown settings
    var spellCooldown: Double = 1.0    // Legacy value retained; runtime timing comes from selected actions
    var potionCooldown: Double = 0.5   // Cooldown for potions (mana + critical when is potion)

    private enum CodingKeys: String, CodingKey {
        case vocation
        case healAction
        case criticalAction
        case healEnabled
        case healThreshold
        case healHotkey
        case criticalEnabled
        case criticalThreshold
        case criticalHotkey
        case criticalIsPotion
        case spiritPotionHeal
        case spiritPotionHotkey
        case spiritPotionThreshold
        case manaEnabled
        case manaThreshold
        case manaHotkey
        case spellCooldown
        case potionCooldown
    }
}

extension HealerConfig {
    init(from decoder: Decoder) throws {
        let defaults = HealerConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vocation = try container.decodeIfPresent(HealingVocation.self, forKey: .vocation)
        healAction = try container.decodeIfPresent(HealingAction.self, forKey: .healAction)
        criticalAction = try container.decodeIfPresent(HealingAction.self, forKey: .criticalAction)
        healEnabled = try container.decodeIfPresent(Bool.self, forKey: .healEnabled) ?? defaults.healEnabled
        healThreshold = try container.decodeIfPresent(Int.self, forKey: .healThreshold) ?? defaults.healThreshold
        healHotkey = try container.decodeIfPresent(String.self, forKey: .healHotkey) ?? defaults.healHotkey
        criticalEnabled = try container.decodeIfPresent(Bool.self, forKey: .criticalEnabled) ?? defaults.criticalEnabled
        criticalThreshold = try container.decodeIfPresent(Int.self, forKey: .criticalThreshold) ?? defaults.criticalThreshold
        criticalHotkey = try container.decodeIfPresent(String.self, forKey: .criticalHotkey) ?? defaults.criticalHotkey
        criticalIsPotion = try container.decodeIfPresent(Bool.self, forKey: .criticalIsPotion) ?? defaults.criticalIsPotion
        spiritPotionHeal = try container.decodeIfPresent(Bool.self, forKey: .spiritPotionHeal) ?? defaults.spiritPotionHeal
        spiritPotionHotkey = try container.decodeIfPresent(String.self, forKey: .spiritPotionHotkey) ?? defaults.spiritPotionHotkey
        spiritPotionThreshold = try container.decodeIfPresent(Int.self, forKey: .spiritPotionThreshold) ?? defaults.spiritPotionThreshold
        manaEnabled = try container.decodeIfPresent(Bool.self, forKey: .manaEnabled) ?? defaults.manaEnabled
        manaThreshold = try container.decodeIfPresent(Int.self, forKey: .manaThreshold) ?? defaults.manaThreshold
        manaHotkey = try container.decodeIfPresent(String.self, forKey: .manaHotkey) ?? defaults.manaHotkey
        spellCooldown = try container.decodeIfPresent(Double.self, forKey: .spellCooldown) ?? defaults.spellCooldown
        potionCooldown = try container.decodeIfPresent(Double.self, forKey: .potionCooldown) ?? defaults.potionCooldown
    }
}

struct MagicShieldConfig: Codable {
    var enabled = false
    var hotkey = "R"
    var threshold = 25

    private enum CodingKeys: String, CodingKey { case enabled, hotkey, threshold }
    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? "R"
        threshold = try container.decodeIfPresent(Int.self, forKey: .threshold) ?? 25
    }
}

/// Eater configuration
struct EaterConfig: Codable {
    var enabled: Bool = false
    var foodType: String = "fire_mushroom"
    var hotkey: String = "]"

    private enum CodingKeys: String, CodingKey {
        case enabled
        case foodType
        case hotkey
    }
}

extension EaterConfig {
    init(from decoder: Decoder) throws {
        let defaults = EaterConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        foodType = try container.decodeIfPresent(String.self, forKey: .foodType) ?? defaults.foodType
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey
    }
}

/// Haste configuration
struct HasteConfig: Codable {
    var enabled: Bool = false
    var hotkey: String = "x"

    private enum CodingKeys: String, CodingKey {
        case enabled
        case hotkey
    }
}

extension HasteConfig {
    init(from decoder: Decoder) throws {
        let defaults = HasteConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey
    }
}

/// Skinner configuration
struct SkinnerConfig: Codable {
    var enabled: Bool = false
    var hotkey: String = "["

    private enum CodingKeys: String, CodingKey {
        case enabled
        case hotkey
    }
}

extension SkinnerConfig {
    init(from decoder: Decoder) throws {
        let defaults = SkinnerConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey
    }
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
    
    // Paladin Combo settings (mutually exclusive with Utito Tempo)
    var paladinComboEnabled: Bool = false  // Trigger combo on ammo decrease

    private enum CodingKeys: String, CodingKey {
        case enabled
        case startStopHotkey
        case comboHotkey
        case lootOnStop
        case autoLootHotkey
        case utitoTempoHotkey
        case utitoTempoEnabled
        case recastUtito
        case paladinComboEnabled
    }
}

extension ComboConfig {
    init(from decoder: Decoder) throws {
        let defaults = ComboConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        startStopHotkey = try container.decodeIfPresent(String.self, forKey: .startStopHotkey) ?? defaults.startStopHotkey
        comboHotkey = try container.decodeIfPresent(String.self, forKey: .comboHotkey) ?? defaults.comboHotkey
        lootOnStop = try container.decodeIfPresent(Bool.self, forKey: .lootOnStop) ?? defaults.lootOnStop
        autoLootHotkey = try container.decodeIfPresent(String.self, forKey: .autoLootHotkey) ?? defaults.autoLootHotkey
        utitoTempoHotkey = try container.decodeIfPresent(String.self, forKey: .utitoTempoHotkey) ?? defaults.utitoTempoHotkey
        utitoTempoEnabled = try container.decodeIfPresent(Bool.self, forKey: .utitoTempoEnabled) ?? defaults.utitoTempoEnabled
        recastUtito = try container.decodeIfPresent(Bool.self, forKey: .recastUtito) ?? defaults.recastUtito
        paladinComboEnabled = try container.decodeIfPresent(Bool.self, forKey: .paladinComboEnabled) ?? defaults.paladinComboEnabled
    }
}

/// A named preset containing all settings
struct PresetConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var regions: RegionConfig = RegionConfig()
    var healer: HealerConfig = HealerConfig()
    var eater: EaterConfig = EaterConfig()
    var haste: HasteConfig = HasteConfig()
    var magicShield = MagicShieldConfig()
    var skinner: SkinnerConfig = SkinnerConfig()
    var combo: ComboConfig = ComboConfig()

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case regions
        case healer
        case eater
        case haste
        case magicShield
        case skinner
        case combo
    }
    
    /// Create preset from current config
    static func fromConfig(_ config: UserConfig, name: String) -> PresetConfig {
        let preset = PresetConfig(
            name: name,
            regions: config.regions,
            healer: config.healer,
            eater: config.eater,
            haste: config.haste,
            magicShield: config.magicShield,
            skinner: config.skinner,
            combo: config.combo
        )
        return preset
    }
}

extension PresetConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Preset"
        regions = try container.decodeIfPresent(RegionConfig.self, forKey: .regions) ?? RegionConfig()
        healer = try container.decodeIfPresent(HealerConfig.self, forKey: .healer) ?? HealerConfig()
        eater = try container.decodeIfPresent(EaterConfig.self, forKey: .eater) ?? EaterConfig()
        haste = try container.decodeIfPresent(HasteConfig.self, forKey: .haste) ?? HasteConfig()
        magicShield = try container.decodeIfPresent(MagicShieldConfig.self, forKey: .magicShield) ?? MagicShieldConfig()
        skinner = try container.decodeIfPresent(SkinnerConfig.self, forKey: .skinner) ?? SkinnerConfig()
        combo = try container.decodeIfPresent(ComboConfig.self, forKey: .combo) ?? ComboConfig()
    }
}

/// Complete user configuration
struct UserConfig: Codable {
    var regions: RegionConfig = RegionConfig()
    var healer: HealerConfig = HealerConfig()
    var eater: EaterConfig = EaterConfig()
    var haste: HasteConfig = HasteConfig()
    var magicShield = MagicShieldConfig()
    var skinner: SkinnerConfig = SkinnerConfig()
    var combo: ComboConfig = ComboConfig()
    
    // Presets support
    var presets: [PresetConfig] = []
    var activePresetId: UUID?

    private enum CodingKeys: String, CodingKey {
        case regions
        case healer
        case eater
        case haste
        case magicShield
        case skinner
        case combo
        case presets
        case activePresetId
    }
    
    /// Apply preset settings to current config
    mutating func applyPreset(_ preset: PresetConfig) {
        regions = preset.regions
        healer = preset.healer
        eater = preset.eater
        haste = preset.haste
        magicShield = preset.magicShield
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
        presets[index].magicShield = magicShield
        presets[index].skinner = skinner
        presets[index].combo = combo
    }
    
    /// Get active preset
    var activePreset: PresetConfig? {
        guard let id = activePresetId else { return nil }
        return presets.first { $0.id == id }
    }


}

extension UserConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        regions = try container.decodeIfPresent(RegionConfig.self, forKey: .regions) ?? RegionConfig()
        healer = try container.decodeIfPresent(HealerConfig.self, forKey: .healer) ?? HealerConfig()
        eater = try container.decodeIfPresent(EaterConfig.self, forKey: .eater) ?? EaterConfig()
        haste = try container.decodeIfPresent(HasteConfig.self, forKey: .haste) ?? HasteConfig()
        magicShield = try container.decodeIfPresent(MagicShieldConfig.self, forKey: .magicShield) ?? MagicShieldConfig()
        skinner = try container.decodeIfPresent(SkinnerConfig.self, forKey: .skinner) ?? SkinnerConfig()
        combo = try container.decodeIfPresent(ComboConfig.self, forKey: .combo) ?? ComboConfig()
        presets = try container.decodeIfPresent([PresetConfig].self, forKey: .presets) ?? []
        activePresetId = try container.decodeIfPresent(UUID.self, forKey: .activePresetId)
    }
}
