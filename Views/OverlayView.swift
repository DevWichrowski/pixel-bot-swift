import SwiftUI
import AppKit

/// Main overlay view containing all tabs
struct OverlayView: View {
    @StateObject private var bot = TibiaBot()
    @State private var currentTab = "status"
    @State private var dragOffset = CGPoint.zero
    @State private var isCollapsed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            if !isCollapsed {
                // Tabs
                tabsView
                
                // Content
                Group {
                    switch currentTab {
                    case "status":
                        StatusView(bot: bot)
                    case "config":
                        ConfigView(bot: bot)
                    case "presets":
                        PresetsView(bot: bot)
                    default:
                        StatusView(bot: bot)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 280, height: isCollapsed ? 32 : 550)
        .background(Theme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.borderHighlight, Theme.borderShadow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // Collapse/Expand button
            Button(action: {
                isCollapsed.toggle()
            }) {
                Text(isCollapsed ? "[+]" : "[-]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)
            
            // Decoration
            Text("◆◇◆")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.accent)
            
            // Title with preset name (only when expanded)
            if !isCollapsed {
                if let preset = bot.presets.first(where: { $0.id == bot.activePresetId }) {
                    Text("PIXEL")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.gold)
                    Text("-")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textDim)
                    Text(preset.name.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                        .lineLimit(1)
                } else {
                    Text("PIXEL BOT")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.gold)
                }
            }
            
            // Status indicator (always visible, more prominent when collapsed)
            HStack(spacing: 4) {
                Circle()
                    .fill(bot.isRunning ? Theme.success : Theme.textDim)
                    .frame(width: 8, height: 8)
                
                if isCollapsed {
                    Text(bot.isRunning ? "RUNNING" : "STOPPED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(bot.isRunning ? Theme.success : Theme.textDim)
                }
            }
            
            Spacer()
            
            // Close button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("[X]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.bgDark)
    }
    
    // MARK: - Tabs
    
    private var tabsView: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.borderHighlight)
                .frame(height: 2)
            
            HStack(spacing: 4) {
                TabButton(
                    title: "[\(Theme.Icons.status) STATUS]",
                    isSelected: currentTab == "status"
                ) {
                    currentTab = "status"
                }
                
                TabButton(
                    title: "[\(Theme.Icons.config) CONFIG]",
                    isSelected: currentTab == "config"
                ) {
                    currentTab = "config"
                }
                
                TabButton(
                    title: "[⚙️ PRESETS]",
                    isSelected: currentTab == "presets"
                ) {
                    currentTab = "presets"
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(Theme.bgPanel)
            
            Rectangle()
                .fill(Theme.borderShadow)
                .frame(height: 2)
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? Theme.accent : Theme.textDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Theme.bgLight : Theme.bgPanel)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keyable Window (allows keyboard input in borderless window)

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay Window

class OverlayWindowController: NSObject {
    private var window: NSWindow?
    
    func showWindow() {
        let contentView = OverlayView()
        
        let window = KeyableWindow(
            contentRect: NSRect(x: 20, y: 100, width: 280, height: 550),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = NSHostingView(rootView: contentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true
        
        // Position on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            window.setFrameOrigin(NSPoint(x: 20, y: screenFrame.height - 650))
        }
        
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
