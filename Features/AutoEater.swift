import Foundation

/// Auto eater that consumes food on a timer
class AutoEater {
    private let keyPress: any KeyPressServicing
    private let keyPressGroup = KeyPressRequestGroup()
    private let delayedActionQueue: DispatchQueue
    private let secondPressDelayOverride: (() -> TimeInterval)?
    
    var enabled: Bool = false
    var hotkey: String = "]"
    var currentFood: String = "fire_mushroom"
    
    private var nextEatTime: Date = .distantFuture
    private var secondPressWorkItem: DispatchWorkItem?
    private var secondPressGeneration = 0
    
    init(
        keyPress: any KeyPressServicing = KeyPressService.shared,
        delayedActionQueue: DispatchQueue = .main,
        secondPressDelayOverride: (() -> TimeInterval)? = nil
    ) {
        self.keyPress = keyPress
        self.delayedActionQueue = delayedActionQueue
        self.secondPressDelayOverride = secondPressDelayOverride
    }

    deinit {
        cancelPendingActions()
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
        cancelPendingActions()
        self.enabled = enabled
        
        if enabled {
            // When enabling, schedule first meal (don't eat immediately)
            let duration = TimeInterval(food.duration * 2)
            let delay = duration + humanRandom(median: 3.0, spread: 0.4, min: 1.0, max: 10.0)
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
    
    func eatNow() {
        // Press hotkey twice with interval
        guard keyPress.pressKey(hotkey, priority: .regular, group: keyPressGroup) else { return }

        secondPressGeneration += 1
        let generation = secondPressGeneration
        let secondPressDelay = secondPressDelayOverride?() ??
            humanRandom(median: 0.3, spread: 0.3, min: 0.15, max: 0.6)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.secondPressGeneration == generation,
                  self.enabled else {
                return
            }

            self.secondPressWorkItem = nil
            self.keyPress.pressKey(self.hotkey, priority: .regular, group: self.keyPressGroup)
        }
        secondPressWorkItem = workItem
        delayedActionQueue.asyncAfter(deadline: .now() + max(0, secondPressDelay), execute: workItem)
        
        // Calculate wait time (duration * 2 for 2 items + random delay)
        let duration = TimeInterval(food.duration * 2)
        let nextMealDelay = duration + humanRandom(median: 3.0, spread: 0.4, min: 1.0, max: 10.0)
        nextEatTime = Date().addingTimeInterval(nextMealDelay)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("🍖 Ate 2x \(food.name). Next meal at \(formatter.string(from: nextEatTime)) (in \(Int(nextMealDelay))s)")
    }

    func cancelPendingActions() {
        secondPressGeneration += 1
        secondPressWorkItem?.cancel()
        secondPressWorkItem = nil
        keyPress.cancelPendingRequests(in: keyPressGroup)
    }
}
