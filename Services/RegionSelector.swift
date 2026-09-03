import Foundation
import AppKit
import SwiftUI

/// Region selector window for picking screen areas
@MainActor
final class RegionSelector: NSObject {
    static let shared = RegionSelector()
    
    private var selectionWindow: NSWindow?
    private var overlayView: RegionOverlayView?
    private var completionHandler: (((x: Int, y: Int, width: Int, height: Int)?) -> Void)?
    private var selectionScreen: NSScreen?
    
    private override init() {
        super.init()
    }
    
    /// Start region selection
    func selectRegion(completion: @escaping ((x: Int, y: Int, width: Int, height: Int)?) -> Void) {
        completionHandler = completion
        showSelectionWindow()
    }
    
    private func showSelectionWindow() {
        // Close any existing window first
        closeWindow()
        
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == CGMainDisplayID()
        }) else {
            completionHandler?(nil)
            return
        }
        
        // Create fullscreen transparent window
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.hasShadow = false
        
        // Create overlay view
        let view = RegionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onComplete = { [weak self] rect in
            self?.finishSelection(rect: rect)
        }
        view.onCancel = { [weak self] in
            self?.cancelSelection()
        }
        
        window.contentView = view
        self.overlayView = view
        self.selectionWindow = window
        self.selectionScreen = screen
        
        // Make key and show
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        
        // Set cursor
        NSCursor.crosshair.push()
        
        print("📍 Region selector opened")
    }
    
    private func finishSelection(rect: NSRect) {
        print("📍 Selection finished: \(rect)")
        
        // Pop cursor first
        NSCursor.pop()
        
        // Get screen height before closing
        let screenHeight = selectionScreen?.frame.height ?? 0
        
        // Close window
        closeWindow()
        
        // Calculate flipped Y (screen coords are flipped)
        let minX = Int(floor(rect.minX))
        let minY = Int(floor(screenHeight - rect.maxY))
        let maxX = Int(ceil(rect.maxX))
        let maxY = Int(ceil(screenHeight - rect.minY))
        
        // Call completion
        let result = (
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        
        completionHandler?(result)
        completionHandler = nil
    }
    
    private func cancelSelection() {
        print("📍 Selection cancelled")
        NSCursor.pop()
        closeWindow()
        completionHandler?(nil)
        completionHandler = nil
    }
    
    private func closeWindow() {
        overlayView?.onComplete = nil
        overlayView?.onCancel = nil
        overlayView = nil
        selectionWindow?.orderOut(nil)
        selectionWindow = nil
        selectionScreen = nil
    }
}

/// Overlay view for drawing selection rectangle
class RegionOverlayView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw semi-transparent overlay
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()
        
        // Draw selection rectangle if active
        if currentRect.width > 0 && currentRect.height > 0 {
            // Clear selection area (make it visible)
            NSGraphicsContext.current?.saveGraphicsState()
            NSColor.clear.setFill()
            currentRect.fill(using: .copy)
            NSGraphicsContext.current?.restoreGraphicsState()
            
            // Draw cyan border
            NSColor.cyan.setStroke()
            let path = NSBezierPath(rect: currentRect)
            path.lineWidth = 3
            path.stroke()
            
            // Draw white inner border
            NSColor.white.setStroke()
            let innerPath = NSBezierPath(rect: currentRect.insetBy(dx: 2, dy: 2))
            innerPath.lineWidth = 1
            innerPath.stroke()
            
            // Draw size label
            let sizeText = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let attrString = NSAttributedString(string: sizeText, attributes: attrs)
            let textSize = attrString.size()
            
            // Draw label background
            let labelRect = NSRect(
                x: currentRect.minX,
                y: currentRect.maxY + 5,
                width: textSize.width + 10,
                height: textSize.height + 6
            )
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()
            
            // Draw label text
            attrString.draw(at: NSPoint(x: labelRect.minX + 5, y: labelRect.minY + 3))
        }
        
        // Draw instructions at top
        let instructions = "Click and drag to select region. Press ESC to cancel."
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: instructions, attributes: attrs)
        let size = attrString.size()
        
        // Background for instructions
        let instrRect = NSRect(
            x: (bounds.width - size.width) / 2 - 10,
            y: bounds.height - 50,
            width: size.width + 20,
            height: size.height + 10
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: instrRect, xRadius: 5, yRadius: 5).fill()
        
        attrString.draw(at: NSPoint(x: instrRect.minX + 10, y: instrRect.minY + 5))
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        isDragging = true
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint, isDragging else { return }
        let current = convert(event.locationInWindow, from: nil)
        
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        
        if currentRect.width > 10 && currentRect.height > 10 {
            // Valid selection
            let handler = onComplete
            DispatchQueue.main.async {
                handler?(self.currentRect)
            }
        } else {
            // Too small, cancel
            let handler = onCancel
            DispatchQueue.main.async {
                handler?()
            }
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            let handler = onCancel
            DispatchQueue.main.async {
                handler?()
            }
        }
    }
}
