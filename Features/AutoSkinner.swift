import Foundation
import Cocoa

/// Auto skinner that triggers hotkey on right mouse click
class AutoSkinner {
    private let keyPress: any KeyPressServicing
    private let keyPressGroup = KeyPressRequestGroup()
    private let delayedActionQueue: DispatchQueue
    private let skinningDelayOverride: (() -> TimeInterval)?
    
    var enabled: Bool = false
    var hotkey: String = "["
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isListening: Bool = false
    private var pendingSkinningWorkItems: [UUID: DispatchWorkItem] = [:]
    private var skinningGeneration = 0
    
    init(
        keyPress: any KeyPressServicing = KeyPressService.shared,
        delayedActionQueue: DispatchQueue = .main,
        skinningDelayOverride: (() -> TimeInterval)? = nil
    ) {
        self.keyPress = keyPress
        self.delayedActionQueue = delayedActionQueue
        self.skinningDelayOverride = skinningDelayOverride
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

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    skinner.reenableEventTap()
                    return Unmanaged.passUnretained(event)
                }
                
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
        cancelPendingActions()

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
        if !enabled {
            stop()
        }
        let status = enabled ? "ENABLED" : "DISABLED"
        print("🔪 Auto Skinner \(status) (Hotkey: \(hotkey))")
    }
    
    func performSkinning() {
        // Wait for the existing randomized delay, then press the hotkey.
        let delay = skinningDelayOverride?() ??
            humanRandom(median: 0.35, spread: 0.35, min: 0.15, max: 0.8)
        let id = UUID()
        let generation = skinningGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSkinningWorkItems.removeValue(forKey: id)
            guard self.skinningGeneration == generation, self.enabled else { return }
            self.keyPress.pressKey(self.hotkey, priority: .regular, group: self.keyPressGroup)
            print("🔪 Skinned! (in \(String(format: "%.3f", delay))s)")
        }
        pendingSkinningWorkItems[id] = workItem
        delayedActionQueue.asyncAfter(deadline: .now() + max(0, delay), execute: workItem)
    }

    func cancelPendingActions() {
        skinningGeneration += 1
        pendingSkinningWorkItems.values.forEach { $0.cancel() }
        pendingSkinningWorkItems.removeAll(keepingCapacity: true)
        keyPress.cancelPendingRequests(in: keyPressGroup)
    }

    private func reenableEventTap() {
        guard enabled, let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        print("🔪 Re-enabled skinner mouse tap")
    }
}
