import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Service for simulating keyboard key presses using CGEvent (non-blocking)
/// Includes hold time mechanisms to ensure game registration
class KeyPressService {
    static let shared = KeyPressService()
    
    private var lastKeyPressTime: Date = .distantPast
    // Global cooldown to prevent spamming
    private var currentMinimumInterval: TimeInterval = 0.05 // 50ms minimum gap between keys
    
    private func randomKeyInterval() -> TimeInterval {
        // Random interval between key presses (not holding time, but gap between presses)
        Double.random(in: 0.05...0.12)
    }
    
    private var canPressKey: Bool {
        Date().timeIntervalSince(lastKeyPressTime) >= currentMinimumInterval
    }
    
    /// Map of key names to CGKeyCode
    private let keyCodeMap: [String: CGKeyCode] = [
        // Function keys
        "f1": CGKeyCode(kVK_F1),
        "f2": CGKeyCode(kVK_F2),
        "f3": CGKeyCode(kVK_F3),
        "f4": CGKeyCode(kVK_F4),
        "f5": CGKeyCode(kVK_F5),
        "f6": CGKeyCode(kVK_F6),
        "f7": CGKeyCode(kVK_F7),
        "f8": CGKeyCode(kVK_F8),
        "f9": CGKeyCode(kVK_F9),
        "f10": CGKeyCode(kVK_F10),
        "f11": CGKeyCode(kVK_F11),
        "f12": CGKeyCode(kVK_F12),
        
        // Letters
        "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B), "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D), "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H), "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N), "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P), "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T), "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V), "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),
        
        // Numbers
        "0": CGKeyCode(kVK_ANSI_0), "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3), "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6), "7": CGKeyCode(kVK_ANSI_7), "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),
        
        // Special keys
        "[": CGKeyCode(kVK_ANSI_LeftBracket),
        "]": CGKeyCode(kVK_ANSI_RightBracket),
        "space": CGKeyCode(kVK_Space),
        "return": CGKeyCode(kVK_Return),
        "escape": CGKeyCode(kVK_Escape),
        "tab": CGKeyCode(kVK_Tab),
        "shift": CGKeyCode(kVK_Shift),
    ]
    
    /// Press a key by name (e.g., "F1", "x", "[")
    /// Uses CGEvent with proper event source for reliable game registration
    func pressKey(_ key: String) {
        guard canPressKey else {
            let elapsed = Date().timeIntervalSince(lastKeyPressTime)
            if elapsed < currentMinimumInterval * 0.5 {
                 // Too spammy to log
            }
            return
        }
        
        let normalizedKey = key.lowercased()
        
        guard let keyCode = keyCodeMap[normalizedKey] else {
            print("⚠️ Unknown key: \(key)")
            return
        }
        
        // Use combinedSessionState to make events appear as real user input
        // This helps prevent the "stuck" state where manual input is needed to unblock
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        
        // Create key down event with proper source
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true) else {
            print("❌ Failed to create key down event")
            return
        }
        
        // Create key up event with proper source
        guard let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            print("❌ Failed to create key up event")
            return
        }
        
        // Post key down to session event tap (more reliable than HID tap for games)
        keyDown.post(tap: .cgSessionEventTap)
        
        // CRITICAL: Hold key for 80-120ms to ensure game registers it
        let holdTime = UInt32.random(in: 50000...100000)
        // print("⏳ [DEBUG] Holding \(key) for \(holdTime/1000)ms...") // Commented out to reduce spam
        usleep(holdTime)
        
        // Post key up
        keyUp.post(tap: .cgSessionEventTap)
        
        lastKeyPressTime = Date()
        currentMinimumInterval = randomKeyInterval()
        print("⌨️ Pressed key: \(key)")
    }
}
