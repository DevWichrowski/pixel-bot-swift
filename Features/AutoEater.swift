import Foundation

/// Auto eater that consumes food on a timer
class AutoEater {
    private let keyPress: KeyPressService
    
    var enabled: Bool = false
    var hotkey: String = "]"
    var currentFood: String = "fire_mushroom"
    
    private var nextEatTime: Date = .distantFuture
    
    init(keyPress: KeyPressService = .shared) {
        self.keyPress = keyPress
    }
    
    /// Get current food type
    var food: FoodType {
        FoodType.all.first { $0.id == currentFood } ?? .fireMushroom
    }
    
    /// Set food type
    func setFoodType(_ foodKey: String) {
        if FoodType.all.contains(where: { $0.id == foodKey }) {
            currentFood = foodKey
            print("🍖 Food set to: \(food.name) (\(food.duration)s)")
        }
    }
    
    /// Toggle auto eater
    func toggle(_ enabled: Bool) {
        self.enabled = enabled
        
        if enabled {
            // When enabling, schedule first meal (don't eat immediately)
            let duration = TimeInterval(food.duration * 2)
            let delay = duration + Double.random(in: 1.0...6.0)
            nextEatTime = Date().addingTimeInterval(delay)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            print("🍖 Auto Eater enabled. First meal at \(formatter.string(from: nextEatTime)) (in \(Int(delay))s)")
        } else {
            print("🍖 Auto Eater disabled")
        }
    }
    
    /// Check if it's time to eat
    func checkAndEat() {
        guard enabled else { return }
        
        if Date() >= nextEatTime {
            eatNow()
        }
    }
    
    private func eatNow() {
        // Press hotkey twice with interval
        keyPress.pressKey(hotkey)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.2...0.4)) { [weak self] in
            self?.keyPress.pressKey(self?.hotkey ?? "]")
        }
        
        // Calculate wait time (duration * 2 for 2 items + random delay)
        let duration = TimeInterval(food.duration * 2)
        let delay = duration + Double.random(in: 1.0...6.0)
        nextEatTime = Date().addingTimeInterval(delay)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("🍖 Ate 2x \(food.name). Next meal at \(formatter.string(from: nextEatTime)) (in \(Int(delay))s)")
    }
}
