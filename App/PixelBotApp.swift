import SwiftUI
import AppKit

@main
struct PixelBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar only)
        NSApp.setActivationPolicy(.accessory)
        
        // Show overlay window
        overlayController = OverlayWindowController()
        overlayController?.showWindow()
        
        // Request permissions
        requestPermissions()
        
        print("🤖 Pixel Bot Swift started!")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🤖 Pixel Bot Swift shutting down...")
    }
    
    private func requestPermissions() {
        // Check Accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessibilityEnabled {
            print("⚠️ Accessibility permission needed for key simulation")
        }
        
        // Screen Recording permission is checked by ScreenCaptureService
    }
}
