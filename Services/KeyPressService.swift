import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Service for simulating keyboard key presses using CGEvent
/// Uses proper event source configuration to ensure reliable game registration
class KeyPressService {
    static let shared = KeyPressService()

    private var lastKeyPressTime: Date = .distantPast
    private var currentMinimumInterval: TimeInterval = 0.05 // 50ms minimum gap between keys

    /// Persistent event source — reused across all presses for consistent state
    private let eventSource: CGEventSource?

    init() {
        eventSource = CGEventSource(stateID: .combinedSessionState)
        // Prevent macOS from suppressing our synthetic events when real input happens nearby
        eventSource?.localEventsSuppressionInterval = 0.0
    }

    private func randomKeyInterval() -> TimeInterval {
        Double.random(in: 0.05...0.15)
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
    /// Key-down, hold, and key-up all happen on the calling thread for reliable game registration.
    /// - Parameter urgent: When true, bypasses the global cooldown (used by healer)
    /// - Returns: true if the key was actually sent, false if blocked
    @discardableResult
    func pressKey(_ key: String, urgent: Bool = false) -> Bool {
        guard urgent || canPressKey else {
            return false
        }

        let normalizedKey = key.lowercased()

        guard let keyCode = keyCodeMap[normalizedKey] else {
            print("⚠️ Unknown key: \(key)")
            return false
        }

        // Create events from the persistent source
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            print("❌ Failed to create key events for: \(key)")
            return false
        }

        // Clear modifier flags — prevents stale shift/ctrl/alt from combinedSessionState
        // leaking into our synthetic presses
        keyDown.flags = []
        keyUp.flags = []

        // Complete key press on the same thread: down → hold → up
        keyDown.post(tap: .cgSessionEventTap)

        let holdTime = UInt32.random(in: 40000...130000)
        usleep(holdTime)

        keyUp.post(tap: .cgSessionEventTap)

        lastKeyPressTime = Date()
        currentMinimumInterval = randomKeyInterval()

        print("⌨️ Pressed key: \(key) (hold: \(holdTime/1000)ms)")
        return true
    }
}
