import SwiftUI

/// Pixel art theme colors and icons
struct Theme {
    // Base colors
    static let bg = Color(hex: "0d0d1a")
    static let bgDark = Color(hex: "08080f")
    static let bgLight = Color(hex: "1a1a2e")
    static let bgPanel = Color(hex: "151525")
    
    // Border colors
    static let borderHighlight = Color(hex: "4a4a6a")
    static let borderShadow = Color(hex: "0a0a15")
    static let borderMid = Color(hex: "2a2a4a")
    
    // Text colors
    static let text = Color(hex: "a0a0c0")
    static let textDim = Color(hex: "606080")
    static let textBright = Color.white
    
    // Status colors
    static let hp = Color(hex: "ff4466")
    static let hpDark = Color(hex: "aa2244")
    static let mana = Color(hex: "00ccff")
    static let manaDark = Color(hex: "0088aa")
    
    // Accent colors
    static let accent = Color(hex: "00f0ff")
    static let accentBright = Color(hex: "80ffff")
    static let gold = Color(hex: "ffd700")
    static let success = Color(hex: "00ff88")
    static let error = Color(hex: "ff3355")
    static let warning = Color(hex: "ffaa00")
    
    // Feature colors
    static let eater = Color(hex: "ffaa00")
    static let haste = Color(hex: "00ff88")
    static let skinner = Color(hex: "ff6600")
    
    // Icons
    struct Icons {
        static let hp = "♥"
        static let mana = "◆"
        static let heal = "✚"
        static let critical = "⚡"
        static let eater = "※"
        static let haste = "»"
        static let skinner = "†"
        static let start = "▶"
        static let stop = "■"
        static let config = "⚙"
        static let status = "◈"
        static let check = "✓"
        static let cross = "✗"
    }
}

// MARK: - Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

// MARK: - Pixel Art Panel

struct PixelArtPanel<Content: View>: View {
    let content: Content
    var backgroundColor: Color = Theme.bgPanel
    
    init(backgroundColor: Color = Theme.bgPanel, @ViewBuilder content: () -> Content) {
        self.backgroundColor = backgroundColor
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(8)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.borderHighlight, Theme.borderShadow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
            )
    }
}

// MARK: - Pixel Button

struct PixelButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    init(_ title: String, color: Color = Theme.accent, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(isPressed ? color.opacity(0.7) : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isPressed ? Theme.bgDark : Theme.bgLight)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        LinearGradient(
                            colors: isPressed ? [Theme.borderShadow, Theme.borderHighlight] : [Theme.borderHighlight, Theme.borderShadow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .offset(y: isPressed ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in
                        isPressed = false
                        action()
                    }
            )
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text("══")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Theme.borderHighlight)
            
            Text("\(icon) \(title)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.gold)
            
            Text(String(repeating: "═", count: 15))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Theme.borderHighlight)
            
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Toggle Row

struct ToggleRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    var hotkey: String? = nil
    
    var body: some View {
        HStack {
            Toggle(isOn: $isOn) {
                HStack(spacing: 4) {
                    Text(icon)
                        .font(.system(size: 10, design: .monospaced))
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(color)
            }
            .toggleStyle(.checkbox)
            
            Spacer()
            
            if let hotkey = hotkey {
                Text("[\(hotkey)]")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.textDim)
            }
        }
    }
}

// MARK: - Threshold Row

struct ThresholdRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    @Binding var threshold: String
    
    var body: some View {
        HStack {
            Toggle(isOn: $isOn) {
                HStack(spacing: 4) {
                    Text(icon)
                        .font(.system(size: 10, design: .monospaced))
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(color)
            }
            .toggleStyle(.checkbox)
            
            Spacer()
            
            Text("@")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.textDim)
            
            TextField("", text: $threshold)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.textBright)
                .frame(width: 40, height: 20)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
            
            Text("%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.textDim)
        }
    }
}

// MARK: - Key Capture Field (for hotkeys including F1-F12)

struct KeyCaptureField: View {
    @Binding var key: String
    @State private var isCapturing = false
    
    var body: some View {
        Button(action: {
            isCapturing = true
        }) {
            Text(key.isEmpty ? "..." : key.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isCapturing ? Theme.accent : Theme.textBright)
                .frame(width: 50, height: 20)
                .background(isCapturing ? Theme.bgLight : Theme.bgDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isCapturing ? Theme.accent : Theme.borderMid, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .background(
            KeyCaptureView(isCapturing: $isCapturing, capturedKey: $key)
        )
    }
}

struct KeyCaptureView: NSViewRepresentable {
    @Binding var isCapturing: Bool
    @Binding var capturedKey: String
    
    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyCapture = { keyName in
            capturedKey = keyName
            isCapturing = false
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isCapturing = isCapturing
        if isCapturing {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyCaptureNSView: NSView {
    var isCapturing = false
    var onKeyCapture: ((String) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        
        let keyName = keyCodeToName(event.keyCode)
        if !keyName.isEmpty {
            onKeyCapture?(keyName)
        }
    }
    
    private func keyCodeToName(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            // Letters
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m",
            
            // Numbers
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            25: "9", 26: "7", 28: "8", 29: "0",
            
            // Symbols
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";",
            42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
            
            // Special keys
            36: "return", 48: "tab", 49: "space", 51: "delete",
            53: "escape",
            
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12"
        ]
        return keyMap[keyCode] ?? ""
    }
}

// MARK: - Hotkey Row with Key Capture

struct HotkeyRow: View {
    let label: String
    @Binding var hotkey: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.text)
            
            Spacer()
            
            KeyCaptureField(key: $hotkey)
        }
    }
}

