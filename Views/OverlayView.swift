import SwiftUI
import AppKit

private enum OverlayTab: String, CaseIterable, Identifiable {
    case status
    case config
    case presets

    var id: Self { self }

    var title: String {
        switch self {
        case .status: "Status"
        case .config: "Config"
        case .presets: "Presets"
        }
    }

    var icon: TibiaAsset {
        switch self {
        case .status: .iconStatus
        case .config: .iconRegion
        case .presets: .iconPermissions
        }
    }
}

/// Main Tactical Pixel HUD containing all tabs.
struct OverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var bot = TibiaBot()
    @State private var currentTab = OverlayTab.status
    @State private var isCollapsed = false

    private let onCollapseChange: (Bool) -> Void

    init(onCollapseChange: @escaping (Bool) -> Void = { _ in }) {
        self.onCollapseChange = onCollapseChange
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if !isCollapsed {
                tabsView

                Group {
                    switch currentTab {
                    case .status:
                        StatusView(bot: bot)
                    case .config:
                        ConfigView(bot: bot)
                    case .presets:
                        PresetsView(bot: bot)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 474)

                PersistentRunControl(bot: bot)
                    .frame(height: 52)
            }
        }
        .frame(width: 340, height: isCollapsed ? 40 : 600)
        .background {
            TibiaAssetImage(.stoneBackground, resizingMode: .tile)
        }
        .tibiaFrame(.frameOuter, insets: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
        .shadow(color: Color.black.opacity(0.55), radius: 3, x: 1, y: 2)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isCollapsed)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 7) {
            Button {
                let collapsed = !isCollapsed
                isCollapsed = collapsed
                onCollapseChange(collapsed)
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(TacticalQuietButtonStyle(tint: Theme.accentBright))
            .tacticalFocusRing(cornerRadius: 3)
            .accessibilityLabel(isCollapsed ? "Expand PixelBot" : "Collapse PixelBot")
            .help(isCollapsed ? "Expand the Tactical Pixel HUD" : "Collapse the Tactical Pixel HUD")

            TibiaAssetImage(.iconStatus)
                .frame(width: 16, height: 16)

            if isCollapsed {
                Text(bundleDisplayName.uppercased())
                    .font(Theme.headingFont())
                    .foregroundStyle(Theme.textBright)
            } else {
                activeTitle
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Rectangle()
                    .fill(bot.runState.tacticalColor)
                    .frame(width: 6, height: 6)

                if isCollapsed {
                    Text(bot.runState.tacticalTitle.uppercased())
                        .font(Theme.dataFont(weight: .semibold))
                        .foregroundStyle(bot.runState.tacticalColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if bot.comboIsActive {
                    Text("⚔")
                        .font(Theme.utilityFont(weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .accessibilityLabel("Combo active")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bot state")
            .accessibilityValue(bot.runState.tacticalTitle)
            .help(bot.runState.tacticalHelp)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(TacticalQuietButtonStyle(tint: Theme.textDim))
            .tacticalFocusRing(cornerRadius: 3)
            .accessibilityLabel("Quit PixelBot")
            .help("Quit PixelBot")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background {
            TibiaAssetImage(
                .titleBar,
                capInsets: EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderMid)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var activeTitle: some View {
        if let preset = bot.presets.first(where: { $0.id == bot.activePresetId }) {
            HStack(spacing: 4) {
                Text(bundleDisplayName.uppercased())
                    .foregroundStyle(Theme.textBright)
                Text("/")
                    .foregroundStyle(Theme.textDim)
                Text(preset.name.uppercased())
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
            }
            .font(Theme.headingFont())
            .help("Active preset: \(preset.name)")
        } else {
            HStack(spacing: 5) {
                Text(bundleDisplayName.uppercased())
                    .foregroundStyle(Theme.textBright)
                Text("v\(AppVersion.current)")
                    .font(Theme.dataFont())
                    .foregroundStyle(Theme.textDim)
            }
            .font(Theme.headingFont())
        }
    }

    private var bundleDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "PixelBot"
    }

    // MARK: - Tabs

    private var tabsView: some View {
        HStack(spacing: 1) {
            ForEach(OverlayTab.allCases) { tab in
                TabButton(
                    title: tab.title,
                    icon: tab.icon,
                    isSelected: currentTab == tab
                ) {
                    currentTab = tab
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 34)
        .background(Theme.bgPanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderMid)
                .frame(height: 1)
        }
    }
}

private struct PersistentRunControl: View {
    @ObservedObject var bot: TibiaBot

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.borderMid)
                .frame(height: 1)

            PixelButton(
                bot.isRunning
                    ? "\(Theme.Icons.stop)  STOP PIXELBOT"
                    : "\(Theme.Icons.start)  START PIXELBOT",
                color: bot.isRunning ? Theme.error : Theme.success,
                fillWidth: true
            ) {
                bot.toggle()
            }
            .help(
                bot.isRunning
                    ? "Stop capture and cancel pending actions"
                    : "Check permissions and start capture"
            )
            .padding(8)
        }
        .frame(height: 52)
        .background {
            TibiaAssetImage(
                .titleBar,
                capInsets: EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
            )
        }
    }
}

private struct TabButton: View {
    let title: String
    let icon: TibiaAsset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                TibiaAssetImage(icon)
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(Theme.utilityFont(weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.textBright : Theme.textDim)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .background {
                TibiaAssetImage(
                    isSelected ? .tabSelectedFrame : .tabFrame,
                    capInsets: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
                )
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? Theme.gold : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tacticalFocusRing(cornerRadius: 0)
        .accessibilityLabel("\(title) tab")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .help("Show \(title.lowercased())")
    }
}

// MARK: - Keyable Window

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay Window

final class OverlayWindowController: NSObject {
    private static let expandedSize = NSSize(width: 340, height: 600)
    private static let collapsedSize = NSSize(width: 340, height: 40)

    private var window: NSWindow?

    func showWindow() {
        let window = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: Self.expandedSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let contentView = OverlayView { [weak window] isCollapsed in
            guard let window else { return }
            Self.resize(window, forCollapsedState: isCollapsed)
        }

        window.contentView = NSHostingView(rootView: contentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true

        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            window.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.minX + 20,
                    y: visibleFrame.maxY - Self.expandedSize.height - 20
                )
            )
        }

        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private static func resize(_ window: NSWindow, forCollapsedState isCollapsed: Bool) {
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let contentSize = isCollapsed ? collapsedSize : expandedSize
        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        let frame = NSRect(
            x: topLeft.x,
            y: topLeft.y - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
        window.setFrame(
            frame,
            display: true,
            animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }
}
