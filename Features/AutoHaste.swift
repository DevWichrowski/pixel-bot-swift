import Foundation

/// Auto haste that recasts every 31-33 seconds
class AutoHaste {
    private let keyPress: KeyPressService
    
    var enabled: Bool = false
    var hotkey: String = "x"
    
    private var nextCastTime: Date = .distantFuture
    
    init(keyPress: KeyPressService = .shared) {
        self.keyPress = keyPress
    }
    
    /// Toggle auto haste
    func toggle(_ enabled: Bool) {
        self.enabled = enabled
        
        if enabled {
            // Schedule first cast (don't cast immediately)
            let delay = Double.random(in: 31.0...33.0)
            nextCastTime = Date().addingTimeInterval(delay)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            print("⚡ Auto Haste ENABLED (Hotkey: \(hotkey)). First cast at \(formatter.string(from: nextCastTime)) (in \(String(format: "%.1f", delay))s)")
        } else {
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
        keyPress.pressKey(hotkey)
        
        // Schedule next cast in 31-33 seconds
        let delay = Double.random(in: 31.0...33.0)
        nextCastTime = Date().addingTimeInterval(delay)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("⚡ Cast Haste. Next cast at \(formatter.string(from: nextCastTime)) (in \(String(format: "%.1f", delay))s)")
    }
}
