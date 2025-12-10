import Foundation
import Cocoa

/// Auto skinner that triggers hotkey on right mouse click
class AutoSkinner {
    private let keyPress: KeyPressService
    
    var enabled: Bool = false
    var hotkey: String = "["
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isListening: Bool = false
    
    init(keyPress: KeyPressService = .shared) {
        self.keyPress = keyPress
    }
    
    deinit {
        stop()
    }
    
    /// Start the mouse listener
    func start() {
        guard !isListening else { return }
        
        // Create event tap for right mouse button
        let eventMask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Get self from refcon
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                
                let skinner = Unmanaged<AutoSkinner>.fromOpaque(refcon).takeUnretainedValue()
                
                if skinner.enabled && type == .rightMouseDown {
                    skinner.performSkinning()
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap for skinner (need Accessibility permission)")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isListening = true
            print("🔪 Skinner listener started")
        }
    }
    
    /// Stop the mouse listener
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isListening = false
        print("🔪 Skinner listener stopped")
    }
    
    /// Toggle auto skinner
    func toggle(_ enabled: Bool) {
        self.enabled = enabled
        let status = enabled ? "ENABLED" : "DISABLED"
        print("🔪 Auto Skinner \(status) (Hotkey: \(hotkey))")
    }
    
    private func performSkinning() {
        // Wait random delay and press hotkey
        let delay = Double.random(in: 0.2...0.4)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.keyPress.pressKey(self.hotkey)
            print("🔪 Skinned! (in \(String(format: "%.3f", delay))s)")
        }
    }
}
