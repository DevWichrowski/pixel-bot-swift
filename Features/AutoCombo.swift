import Foundation
import Cocoa

/// Auto Combo - presses combo key every 2-2.1 seconds when active
class AutoCombo {
    private let keyPress: KeyPressService
    
    /// Combo hotkey to press
    var comboHotkey: String = "2"
    
    /// Start/Stop hotkey
    var startStopHotkey: String = "v"
    
    /// Auto loot settings
    var lootOnStop: Bool = true
    var autoLootHotkey: String = "space"
    
    /// Utito Tempo settings
    var utitoTempoHotkey: String = "F8"
    var utitoTempoEnabled: Bool = false
    var recastUtito: Bool = false
    
    /// Is combo active
    var isActive: Bool = false
    
    /// Feature enabled
    var enabled: Bool = false
    
    /// Combo interval range (2.0 to 2.1 seconds)
    private let comboIntervalMin: TimeInterval = 2.0
    private let comboIntervalMax: TimeInterval = 2.1
    private var nextInterval: TimeInterval = 2.0
    private var lastPressTime: Date = .distantPast
    
    /// Utito Tempo timing
    private var lastUtitoTime: Date = .distantPast
    private let utitoDuration: TimeInterval = 10.0  // Effect duration
    private let utitoCooldown: TimeInterval = 2.0   // Cooldown (not used in logic)
    
    /// Keyboard listener
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isListening: Bool = false
    
    /// UI callback
    var onActiveChanged: ((Bool) -> Void)?
    
    init(keyPress: KeyPressService = .shared) {
        self.keyPress = keyPress
        randomizeInterval()
    }
    
    deinit {
        stopListener()
    }
    
    private func randomizeInterval() {
        nextInterval = Double.random(in: comboIntervalMin...comboIntervalMax)
    }
    
    func startListener() {
        guard !isListening else { return }
        
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let combo = Unmanaged<AutoCombo>.fromOpaque(refcon).takeUnretainedValue()
                if combo.enabled && type == .keyDown {
                    combo.handleKeyDown(event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create keyboard tap for combo")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isListening = true
            print("⚔️ Combo listener started")
        }
    }
    
    func stopListener() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isListening = false
    }
    
    /// Re-enable tap if system disabled it
    private func ensureTapEnabled() {
        guard let tap = eventTap else {
            // Tap was destroyed, restart listener
            if enabled && !isListening {
                isListening = false  // Reset flag
                startListener()
            }
            return
        }
        
        // Check if tap is still enabled
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            print("⚔️ Re-enabled combo keyboard tap")
        }
    }
    
    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let key = keyCodeToString(Int(keyCode))
        
        if key.lowercased() == startStopHotkey.lowercased() {
            toggleActive()
        }
    }
    
    private func keyCodeToString(_ keyCode: Int) -> String {
        let keyMap: [Int: String] = [
            // Letters
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m",
            // Numbers
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            25: "9", 26: "7", 28: "8", 29: "0",
            // Symbols
            24: "=", 27: "-", 30: "]", 33: "[", 49: "space",
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12"
        ]
        return keyMap[keyCode] ?? ""
    }
    
    func toggle(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            startListener()
        } else {
            isActive = false
            onActiveChanged?(false)
        }
        print(enabled ? "⚔️ Auto Combo ENABLED" : "⚔️ Auto Combo DISABLED")
    }
    
    func toggleActive() {
        guard enabled else { return }
        
        let wasActive = isActive
        isActive = !isActive
        
        if isActive {
            randomizeInterval()
            
            // Use Utito Tempo if enabled
            if utitoTempoEnabled {
                keyPress.pressKey(utitoTempoHotkey)
                lastUtitoTime = Date()
                print("⚡ Utito Tempo CAST")
                
                // Start combo 0.2-0.3s after Utito Tempo
                let delay = Double.random(in: 0.2...0.3)
                lastPressTime = Date().addingTimeInterval(-nextInterval + delay)
            } else {
                lastPressTime = .distantPast
            }
            
            print("⚔️ Combo STARTED")
        } else {
            print("⚔️ Combo STOPPED")
            
            // Press auto loot after stopping (if enabled)
            if wasActive && lootOnStop {
                let delay = Double.random(in: 0.2...0.4)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    self.keyPress.pressKey(self.autoLootHotkey)
                    print("📦 Auto Loot pressed after combo stop")
                }
            }
        }
        
        onActiveChanged?(isActive)
    }
    
    /// Called from main loop - presses combo every 2-2.1s when active
    func checkAndPress() {
        guard enabled else { return }
        
        // Ensure keyboard tap is still active
        ensureTapEnabled()
        
        guard isActive else { return }
        
        let now = Date()
        
        // Re-cast Utito Tempo every 10 seconds if enabled
        if recastUtito && utitoTempoEnabled {
            if now.timeIntervalSince(lastUtitoTime) >= utitoDuration {
                keyPress.pressKey(utitoTempoHotkey)
                lastUtitoTime = now
                print("⚡ Utito Tempo RE-CAST")
            }
        }
        
        // Press combo key at regular interval
        if now.timeIntervalSince(lastPressTime) >= nextInterval {
            keyPress.pressKey(comboHotkey)
            lastPressTime = now
            randomizeInterval()  // New random interval for next press
        }
    }
}
