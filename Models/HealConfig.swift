import Foundation

/// Configuration for a heal type (normal, critical, mana)
struct HealConfig: Codable {
    var enabled: Bool
    var threshold: Int  // Heal when below this %
    var hotkey: String
    
    init(enabled: Bool = false, threshold: Int = 75, hotkey: String = "F1") {
        self.enabled = enabled
        self.threshold = threshold
        self.hotkey = hotkey
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
