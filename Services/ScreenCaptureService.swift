import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

/// Service for capturing screen regions using ScreenCaptureKit
class ScreenCaptureService {
    static let shared = ScreenCaptureService()
    
    /// Retina display scale factor
    private(set) var scaleFactor: CGFloat = 1.0
    
    init() {
        detectScale()
    }
    
    /// Detect Retina display scaling
    private func detectScale() {
        if let screen = NSScreen.main {
            scaleFactor = screen.backingScaleFactor
            print("📺 Display scale factor: \(scaleFactor)")
        }
    }
    
    /// Capture the entire screen and return as CGImage
    func captureScreen() -> CGImage? {
        // Use simple CGWindowListCreateImage for speed
        let displayID = CGMainDisplayID()
        let screenRect = CGDisplayBounds(displayID)
        
        guard let image = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            print("❌ Failed to capture screen")
            return nil
        }
        
        return image
    }
    
    /// Crop a region from screenshot
    /// - Parameters:
    ///   - image: Source image
    ///   - region: Region in logical coordinates (will be scaled for Retina)
    func cropRegion(from image: CGImage, region: (x: Int, y: Int, width: Int, height: Int)) -> CGImage? {
        // Scale for Retina display
        let scaledRect = CGRect(
            x: CGFloat(region.x) * scaleFactor,
            y: CGFloat(region.y) * scaleFactor,
            width: CGFloat(region.width) * scaleFactor,
            height: CGFloat(region.height) * scaleFactor
        )
        
        return image.cropping(to: scaledRect)
    }
    
    /// Check if screen recording permission is granted
    func checkPermission() -> Bool {
        // Try to capture - will trigger permission dialog if needed
        let hasPermission = CGPreflightScreenCaptureAccess()
        if !hasPermission {
            CGRequestScreenCaptureAccess()
        }
        return hasPermission
    }
}
