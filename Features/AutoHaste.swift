import Foundation

/// Auto haste that recasts every 31-33 seconds
class AutoHaste {
    private let keyPress: any KeyPressServicing
    private let keyPressGroup = KeyPressRequestGroup()
    
    var enabled: Bool = false
    var hotkey: String = "x"
    
    private var nextCastTime: Date = .distantFuture
    
    init(keyPress: any KeyPressServicing = KeyPressService.shared) {
        self.keyPress = keyPress
    }

    deinit {
        cancelPendingActions()
    }
    
    /// Toggle auto haste
    func toggle(_ enabled: Bool) {
        self.enabled = enabled
        
        if enabled {
            // Schedule first cast (don't cast immediately)
            let delay = humanRandom(median: 32.0, spread: 0.06, min: 30.5, max: 38.0)
            nextCastTime = Date().addingTimeInterval(delay)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            print("⚡ Auto Haste ENABLED (Hotkey: \(hotkey)). First cast at \(formatter.string(from: nextCastTime)) (in \(String(format: "%.1f", delay))s)")
        } else {
            cancelPendingActions()
            print("⚡ Auto Haste DISABLED")
        }
    }
    
    /// Check if it's time to cast haste
    func checkAndCast() {
        guard enabled else { return }
        
        if Date() >= nextCastTime {
            castNow()
        }
    }
    
    private func castNow() {
        keyPress.pressKey(hotkey, priority: .regular, group: keyPressGroup)
        
        // Schedule the next cast with the existing randomized variance.
        let delay = humanRandom(median: 32.0, spread: 0.06, min: 30.5, max: 38.0)
        nextCastTime = Date().addingTimeInterval(delay)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("⚡ Cast Haste. Next cast at \(formatter.string(from: nextCastTime)) (in \(String(format: "%.1f", delay))s)")
    }

    func cancelPendingActions() {
        keyPress.cancelPendingRequests(in: keyPressGroup)
    }
}
