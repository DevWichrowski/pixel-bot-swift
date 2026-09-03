import SwiftUI
import AppKit

/// Bitmap HUD colors, typography, and the original PixelBot icon vocabulary.
struct Theme {
    // Core palette
    static let bg = Color(hex: "343531")
    static let bgDark = Color(hex: "1D1E1C")
    static let bgLight = Color(hex: "50514D")
    static let bgPanel = Color(hex: "41423E")

    // Structure
    static let borderHighlight = Color(hex: "777872")
    static let borderShadow = Color(hex: "121311")
    static let borderMid = Color(hex: "5B5C57")

    // Text
    static let text = Color(hex: "D3D3CB")
    static let textDim = Color(hex: "A7A8A2")
    static let textBright = Color(hex: "F0F0E8")

    // Vitals
    static let hp = Color(hex: "D74848")
    static let hpDark = Color(hex: "6F2929")
    static let mana = Color(hex: "3B75B7")
    static let manaDark = Color(hex: "233E61")

    // Accents and feature colors
    static let accent = Color(hex: "7797B5")
    static let accentBright = Color(hex: "B7C9D8")
    static let gold = Color(hex: "C2A547")
    static let success = Color(hex: "55A95E")
    static let error = Color(hex: "D74848")
    static let warning = Color(hex: "C2A547")
    static let eater = Color(hex: "B9824C")
    static let haste = Color(hex: "4F89C5")
    static let skinner = Color(hex: "A4A59F")

    static func headingFont(size: CGFloat = 13) -> Font {
        .system(size: max(12, size), weight: .semibold, design: .default)
    }

    static func utilityFont(size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: max(12, size), weight: weight, design: .default)
    }

    static func dataFont(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: max(12, size), weight: weight, design: .monospaced)
    }

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

// MARK: - Bitmap assets

struct TibiaAssetImage: View {
    let asset: TibiaAsset
    let capInsets: EdgeInsets
    let resizingMode: Image.ResizingMode

    init(
        _ asset: TibiaAsset,
        capInsets: EdgeInsets = EdgeInsets(),
        resizingMode: Image.ResizingMode = .stretch
    ) {
        self.asset = asset
        self.capInsets = capInsets
        self.resizingMode = resizingMode
    }

    var body: some View {
        Group {
            if let image = TibiaSkin.image(for: asset) {
                Image(nsImage: image)
                    .resizable(capInsets: capInsets, resizingMode: resizingMode)
                    .interpolation(.none)
            } else {
                Theme.bgPanel
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TibiaSymbol: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Group {
            if let asset = asset {
                TibiaAssetImage(asset)
                    .frame(width: 17, height: 17)
            } else {
                Text(symbol)
                    .foregroundStyle(tint)
            }
        }
        .accessibilityHidden(true)
    }

    private var asset: TibiaAsset? {
        switch symbol {
        case Theme.Icons.hp: .iconHP
        case Theme.Icons.mana: .iconMana
        case Theme.Icons.heal, Theme.Icons.critical, "🧪": .iconHealing
        case Theme.Icons.eater, "📦": .iconEating
        case Theme.Icons.haste, "⏱", "🔄": .iconHaste
        case Theme.Icons.skinner: .iconSkinning
        case Theme.Icons.status: .iconStatus
        case Theme.Icons.config, "◎", "🏹": .iconRegion
        case "⚔": .iconCombo
        case "♪": .iconPermissions
        default: nil
        }
    }
}

private struct TibiaFrameModifier: ViewModifier {
    let asset: TibiaAsset
    let insets: EdgeInsets

    func body(content: Content) -> some View {
        content
            .background(Theme.bgPanel)
            .overlay {
                TibiaAssetImage(asset, capInsets: insets)
                    .mask {
                        Rectangle().strokeBorder(lineWidth: 3)
                    }
            }
    }
}

extension View {
    func tibiaFrame(
        _ asset: TibiaAsset,
        insets: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    ) -> some View {
        modifier(TibiaFrameModifier(asset: asset, insets: insets))
    }
}

// MARK: - Focus treatment

private struct TacticalFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .overlay {
                Rectangle()
                    .stroke(Theme.textBright, lineWidth: 1)
                    .padding(-1)
                    .opacity(isFocused ? 1 : 0)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func tacticalFocusRing(cornerRadius: CGFloat = 4) -> some View {
        modifier(TacticalFocusRingModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Panels

struct PixelArtPanel<Content: View>: View {
    let content: Content
    var backgroundColor: Color = Theme.bgPanel

    init(backgroundColor: Color = Theme.bgPanel, @ViewBuilder content: () -> Content) {
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(7)
            .background(backgroundColor)
            .tibiaFrame(.panelFrame)
    }
}

struct TacticalInsetPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(6)
            .background(Theme.bg)
            .tibiaFrame(.fieldFrame, insets: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
    }
}

// MARK: - Buttons

struct TacticalButtonStyle: ButtonStyle {
    let tint: Color
    var fillsWidth = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.utilityFont(weight: .semibold))
            .foregroundStyle(Theme.textBright)
            .padding(.horizontal, compact ? 8 : 12)
            .frame(
                maxWidth: fillsWidth ? CGFloat.infinity : nil,
                minHeight: compact ? 24 : 30
            )
            .background(Theme.bgLight)
            .overlay {
                TibiaAssetImage(
                    configuration.isPressed ? .buttonPressedFrame : .buttonFrame,
                    capInsets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
                )
                .mask {
                    Rectangle().strokeBorder(lineWidth: 3)
                }
            }
            .overlay {
                Rectangle()
                    .strokeBorder(tint.opacity(configuration.isPressed ? 0.95 : 0.55), lineWidth: 1)
                    .padding(2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.38)
    }
}

struct TacticalQuietButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.utilityFont(weight: .semibold))
            .foregroundStyle(configuration.isPressed ? tint.opacity(0.65) : tint)
            .padding(5)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Theme.bgLight : Color.clear)
            .overlay {
                Rectangle()
                    .strokeBorder(configuration.isPressed ? tint.opacity(0.65) : Color.clear, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.38)
    }
}

struct PixelButton: View {
    let title: String
    let color: Color
    let fillWidth: Bool
    let compact: Bool
    let action: () -> Void

    init(
        _ title: String,
        color: Color = Theme.accent,
        fillWidth: Bool = false,
        compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.fillWidth = fillWidth
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .frame(maxWidth: fillWidth ? .infinity : nil)
        }
        .buttonStyle(TacticalButtonStyle(tint: color, fillsWidth: fillWidth, compact: compact))
        .tacticalFocusRing()
        .accessibilityLabel(title)
    }
}

// MARK: - Section headers

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            TibiaSymbol(symbol: icon, tint: Theme.gold)

            Text(title)
                .font(Theme.headingFont())
                .foregroundStyle(Theme.textBright)
                .tracking(0.6)

            Rectangle()
                .fill(Theme.borderMid)
                .frame(height: 1)
        }
        .font(Theme.utilityFont(weight: .semibold))
        .padding(.vertical, 1)
    }
}

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        icon: String,
        tint: Color = Theme.gold,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    TibiaSymbol(symbol: icon, tint: tint)

                    Text(title)
                        .font(Theme.headingFont())
                        .foregroundStyle(Theme.textBright)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tacticalFocusRing(cornerRadius: 0)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Divider()
                    .overlay(Theme.borderMid)

                content
                    .padding(8)
            }
        }
        .background(Theme.bgPanel)
        .tibiaFrame(.panelFrame)
    }
}

// MARK: - Native control skins

struct TibiaCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                TibiaAssetImage(configuration.isOn ? .checkboxOn : .checkboxOff)
                    .frame(width: 16, height: 16)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tacticalFocusRing(cornerRadius: 0)
    }
}

struct TibiaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textBright)
            .padding(.horizontal, 6)
            .frame(minHeight: 24)
            .background(Theme.bgDark)
            .tibiaFrame(.fieldFrame, insets: EdgeInsets(top: 11, leading: 11, bottom: 11, trailing: 11))
    }
}

// MARK: - Configuration rows

struct ToggleRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    var hotkey: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 6) {
                    TibiaSymbol(symbol: icon, tint: color)
                    Text(label)
                        .font(Theme.utilityFont(weight: .medium))
                }
                .foregroundStyle(color)
            }
            .toggleStyle(TibiaCheckboxStyle())
            .accessibilityLabel(label)

            Spacer(minLength: 6)

            if let hotkey {
                Text("[\(hotkey.uppercased())]")
                    .font(Theme.dataFont())
                    .foregroundStyle(Theme.textDim)
                    .accessibilityLabel("Hotkey \(hotkey)")
            }
        }
        .frame(minHeight: 26)
    }
}

struct ThresholdRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    @Binding var threshold: String

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 6) {
                    TibiaSymbol(symbol: icon, tint: color)
                    Text(label)
                        .font(Theme.utilityFont(weight: .medium))
                }
                .foregroundStyle(color)
            }
            .toggleStyle(TibiaCheckboxStyle())
            .accessibilityLabel(label)

            Spacer(minLength: 4)

            TextField("Percent", text: $threshold)
                .font(Theme.dataFont())
                .monospacedDigit()
                .frame(width: 52)
                .textFieldStyle(TibiaTextFieldStyle())
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(label) threshold")

            Text("%")
                .font(Theme.dataFont())
                .foregroundStyle(Theme.textDim)
        }
        .frame(minHeight: 28)
    }
}

struct LabeledTextFieldRow: View {
    let label: String
    let suffix: String?
    @Binding var text: String
    var width: CGFloat = 64

    init(label: String, text: Binding<String>, suffix: String? = nil, width: CGFloat = 64) {
        self.label = label
        _text = text
        self.suffix = suffix
        self.width = width
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.utilityFont())
                .foregroundStyle(Theme.text)

            Spacer()

            TextField(label, text: $text)
                .font(Theme.dataFont())
                .monospacedDigit()
                .frame(width: width)
                .textFieldStyle(TibiaTextFieldStyle())
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)

            if let suffix {
                Text(suffix)
                    .font(Theme.dataFont())
                    .foregroundStyle(Theme.textDim)
            }
        }
        .frame(minHeight: 28)
    }
}

// MARK: - Key capture

struct KeyCaptureField: View {
    let accessibilityName: String
    @Binding var key: String
    @State private var isCapturing = false

    init(accessibilityName: String = "Hotkey", key: Binding<String>) {
        self.accessibilityName = accessibilityName
        _key = key
    }

    var body: some View {
        Button {
            isCapturing = true
        } label: {
            Text(isCapturing ? "Press key" : (key.isEmpty ? "Unset" : key.uppercased()))
                .font(Theme.dataFont(weight: .semibold))
                .frame(minWidth: 54)
        }
        .buttonStyle(TacticalButtonStyle(tint: isCapturing ? Theme.accentBright : Theme.textBright, compact: true))
        .tacticalFocusRing()
        .background {
            KeyCaptureView(isCapturing: $isCapturing, capturedKey: $key)
        }
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(isCapturing ? "Waiting for a key" : key)
        .help("Click, then press the key you want to assign")
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

final class KeyCaptureNSView: NSView {
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
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            25: "9", 26: "7", 28: "8", 29: "0",
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";",
            42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
            36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12"
        ]
        return keyMap[keyCode] ?? ""
    }
}

struct HotkeyRow: View {
    let label: String
    @Binding var hotkey: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.utilityFont())
                .foregroundStyle(Theme.text)

            Spacer()

            KeyCaptureField(accessibilityName: "\(label) hotkey", key: $hotkey)
        }
        .frame(minHeight: 30)
    }
}
