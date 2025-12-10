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

/// Complete user configuration
struct UserConfig: Codable {
    var regions: RegionConfig = RegionConfig()
    var healer: HealerConfig = HealerConfig()
    var eater: EaterConfig = EaterConfig()
    var haste: HasteConfig = HasteConfig()
    var skinner: SkinnerConfig = SkinnerConfig()
}
