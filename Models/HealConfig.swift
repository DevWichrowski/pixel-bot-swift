import Foundation

enum HealingVocation: String, Codable, CaseIterable {
    case knight, paladin, sorcerer, druid, monk

    var displayName: String {
        switch self {
        case .knight: return "Knight / Elite Knight"
        case .paladin: return "Paladin / Royal Paladin"
        case .sorcerer: return "Sorcerer / Master Sorcerer"
        case .druid: return "Druid / Elder Druid"
        case .monk: return "Monk / Exalted Monk"
        }
    }
}

/// Verified base cooldowns, independent of hotkeys and Wheel of Destiny upgrades.
enum HealingAction: String, Codable, CaseIterable {
    case magicPatch, lightHealing, intenseHealing, ultimateHealing, restoration
    case divineHealing, salvation, bruiseBane, woundCleansing, fairWoundCleansing
    case intenseWoundCleansing, spiritMend, recovery, intenseRecovery

    var name: String {
        switch self {
        case .magicPatch: return "Magic Patch"
        case .lightHealing: return "Light Healing"
        case .intenseHealing: return "Intense Healing"
        case .ultimateHealing: return "Ultimate Healing"
        case .restoration: return "Restoration"
        case .divineHealing: return "Divine Healing"
        case .salvation: return "Salvation"
        case .bruiseBane: return "Bruise Bane"
        case .woundCleansing: return "Wound Cleansing"
        case .fairWoundCleansing: return "Fair Wound Cleansing"
        case .intenseWoundCleansing: return "Intense Wound Cleansing"
        case .spiritMend: return "Spirit Mend"
        case .recovery: return "Recovery"
        case .intenseRecovery: return "Intense Recovery"
        }
    }

    var incantation: String {
        switch self {
        case .magicPatch: return "exura infir"
        case .lightHealing: return "exura"
        case .intenseHealing: return "exura gran"
        case .ultimateHealing: return "exura vita"
        case .restoration: return "exura max vita"
        case .divineHealing: return "exura san"
        case .salvation: return "exura gran san"
        case .bruiseBane: return "exura infir ico"
        case .woundCleansing: return "exura ico"
        case .fairWoundCleansing: return "exura med ico"
        case .intenseWoundCleansing: return "exura gran ico"
        case .spiritMend: return "exura gran tio"
        case .recovery: return "utura"
        case .intenseRecovery: return "utura gran"
        }
    }

    var displayName: String { "\(incantation) · \(name)" }

    var vocations: [HealingVocation] {
        switch self {
        case .magicPatch, .lightHealing, .intenseHealing: return [.druid, .sorcerer, .paladin, .monk]
        case .ultimateHealing, .restoration: return [.druid, .sorcerer]
        case .divineHealing, .salvation: return [.paladin]
        case .bruiseBane, .woundCleansing, .fairWoundCleansing, .intenseWoundCleansing: return [.knight]
        case .spiritMend: return [.monk]
        case .recovery, .intenseRecovery: return [.knight, .paladin]
        }
    }

    var isEmergencyHealing: Bool { self != .recovery && self != .intenseRecovery }

    func supports(vocation: HealingVocation?) -> Bool {
        vocation.map { vocations.contains($0) } ?? true
    }

    static func choices(for vocation: HealingVocation?) -> [HealingAction] {
        allCases.filter { $0.isEmergencyHealing && $0.supports(vocation: vocation) }
    }

    var groupCooldown: TimeInterval {
        switch self {
        case .bruiseBane, .woundCleansing, .fairWoundCleansing, .intenseWoundCleansing: return 2
        default: return 1
        }
    }

    var individualCooldown: TimeInterval {
        switch self {
        case .restoration: return 6
        case .intenseWoundCleansing: return 120
        case .recovery, .intenseRecovery: return 60
        case .bruiseBane, .woundCleansing, .fairWoundCleansing: return 2
        default: return 1
        }
    }

    var officialURL: URL? {
        URL(string: "https://www.tibia.com/library/?spell=\(rawValue.lowercased())&subtopic=spells")
    }

    var secondaryURL: URL? {
        URL(string: "https://www.tibiawiki.com.br/wiki/\(name.replacingOccurrences(of: " ", with: "_"))")
    }
}

/// Configuration for a heal type (normal, critical, mana)
struct HealConfig: Codable {
    var enabled: Bool
    var threshold: Int  // Heal when below this %
    var hotkey: String
    var action: HealingAction?
    
    init(enabled: Bool = false, threshold: Int = 75, hotkey: String = "F1", action: HealingAction? = nil) {
        self.enabled = enabled
        self.threshold = threshold
        self.hotkey = hotkey
        self.action = action
    }
}

/// Food type definition
struct FoodType: Identifiable {
    let id: String
    let name: String
    let duration: Int  // Duration in seconds for one item
    
    static let fireMushroom = FoodType(id: "fire_mushroom", name: "Fire Mushroom", duration: 432)
    static let brownMushroom = FoodType(id: "brown_mushroom", name: "Brown Mushroom", duration: 264)
    
    static let all: [FoodType] = [.fireMushroom, .brownMushroom]
}
