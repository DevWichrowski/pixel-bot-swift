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
    var utitoTempoEnabled: Bool = false {
        didSet {
            if utitoTempoEnabled && paladinComboEnabled {
                paladinComboEnabled = false
            }
        }
    }
    var recastUtito: Bool = false
    
    /// Paladin Combo settings (mutually exclusive with Utito Tempo)
    var paladinComboEnabled: Bool = false {
        didSet {
            if paladinComboEnabled && utitoTempoEnabled {
                utitoTempoEnabled = false
            }
        }
    }
    
    /// Is combo active
    var isActive: Bool = false
    
    /// Feature enabled
    var enabled: Bool = false
    
    /// Combo interval (log-normal around 2.0s)
    private var nextInterval: TimeInterval = 2.0
    private var lastPressTime: Date = .distantPast
    
    /// Utito Tempo timing
    private var lastUtitoTime: Date = .distantPast
    private let utitoDurationMin: TimeInterval = 9.0   // Min random duration
    private let utitoDurationMax: TimeInterval = 12.0  // Max random duration
    private var currentUtitoDuration: TimeInterval = 10.0  // Current random duration
    private let utitoCooldown: TimeInterval = 2.0   // Cooldown (not used in logic)
    
    /// Generate random Utito duration using log-normal (median ~10.5s)
    private func randomUtitoDuration() -> TimeInterval {
        return humanRandom(median: 10.5, spread: 0.1, min: 9.0, max: 13.0)
    }
    
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
        nextInterval = humanRandom(median: 2.0, spread: 0.1, min: 1.8, max: 2.6)
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
                currentUtitoDuration = randomUtitoDuration()
                print("⚡ Utito Tempo CAST (next recast in \(String(format: "%.1f", currentUtitoDuration))s)")
                
                // Start combo after Utito Tempo with human-like delay
                let delay = humanRandom(median: 0.25, spread: 0.25, min: 0.15, max: 0.5)
                lastPressTime = Date().addingTimeInterval(-nextInterval + delay)
            } else {
                lastPressTime = .distantPast
            }
            
            print("⚔️ Combo STARTED")
        } else {
            print("⚔️ Combo STOPPED")
            
            // Press auto loot after stopping (if enabled)
            if wasActive && lootOnStop {
                let delay = humanRandom(median: 0.3, spread: 0.3, min: 0.15, max: 0.6)
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
        
        // Re-cast Utito Tempo with random interval 9-12 seconds if enabled
        if recastUtito && utitoTempoEnabled {
            if now.timeIntervalSince(lastUtitoTime) >= currentUtitoDuration {
                keyPress.pressKey(utitoTempoHotkey)
                lastUtitoTime = now
                currentUtitoDuration = randomUtitoDuration()
                print("⚡ Utito Tempo RE-CAST (next recast in \(String(format: "%.1f", currentUtitoDuration))s)")
            }
        }
        
        // Press combo key at regular interval (only in standard mode, not Paladin Combo)
        if !paladinComboEnabled && now.timeIntervalSince(lastPressTime) >= nextInterval {
            keyPress.pressKey(comboHotkey)
            lastPressTime = now
            randomizeInterval()
        }
    }
    
    /// Paladin Combo timing — cooldown stored per-cast, not re-rolled each tick
    private var lastPaladinComboTime: Date = .distantPast
    private var currentPaladinCooldown: TimeInterval = 0.7

    func checkPaladinCombo(ammoDecreased: Bool) {
        guard enabled && isActive && paladinComboEnabled && ammoDecreased else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPaladinComboTime) >= currentPaladinCooldown else { return }

        lastPaladinComboTime = now
        currentPaladinCooldown = humanRandom(median: 0.7, spread: 0.2, min: 0.5, max: 1.1)
        keyPress.pressKey(comboHotkey)
        print("🏹 Paladin Combo triggered (ammo decreased)")
    }
}
