import SwiftUI
import AppKit

/// Main overlay view containing all tabs
struct OverlayView: View {
    @StateObject private var bot = TibiaBot()
    @State private var currentTab = "status"
    @State private var dragOffset = CGPoint.zero
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Tabs
            tabsView
            
            // Content
            Group {
                switch currentTab {
                case "status":
                    StatusView(bot: bot)
                case "config":
                    ConfigView(bot: bot)
                default:
                    StatusView(bot: bot)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 280, height: 550)
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
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // Decoration
            Text("◆◇◆")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.accent)
            
            // Title
            Text("PIXEL BOT")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.gold)
            
            Text("v2")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.textDim)
            
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
            .onHover { hovering in
                // Could add hover effect here
            }
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

// MARK: - Overlay Window

class OverlayWindowController: NSObject {
    private var window: NSWindow?
    
    func showWindow() {
        let contentView = OverlayView()
        
        let window = NSWindow(
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
