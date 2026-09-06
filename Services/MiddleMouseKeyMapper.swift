import CoreGraphics
import Foundation

/// Maps middle clicks to V only while enabled for the selected foreground client.
final class MiddleMouseKeyMapper {
    var enabled = false
    var inputAllowed: () -> Bool = { true }
    private static let middleButtonNumber: Int64 = 2

    private let keyPress: any KeyPressServicing
    private let ownedKeyPress: KeyPressService?
    private let keyPressGroup = KeyPressRequestGroup()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init() {
        let keyPress = KeyPressService(diagnosticLogger: PixelBotDiagnosticLogger.shared)
        self.keyPress = keyPress
        ownedKeyPress = keyPress
    }

    init(keyPress: any KeyPressServicing) {
        self.keyPress = keyPress
        ownedKeyPress = nil
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        ownedKeyPress?.resume()

        let eventMask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let mapper = Unmanaged<MiddleMouseKeyMapper>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    mapper.reenableEventTap()
                    return Unmanaged.passUnretained(event)
                }

                let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
                if mapper.handleMouseEvent(type: type, buttonNumber: buttonNumber) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create middle mouse mapper tap (need Accessibility permission)")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("🖱️ Middle mouse mapper started (V)")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        if let ownedKeyPress {
            ownedKeyPress.cancelAll()
        } else {
            keyPress.cancelPendingRequests(in: keyPressGroup)
        }
    }

    /// Returns true when the original mouse event should be suppressed.
    @discardableResult
    func handleMouseEvent(type: CGEventType, buttonNumber: Int64) -> Bool {
        guard enabled, inputAllowed(), buttonNumber == Self.middleButtonNumber else { return false }

        if type == .otherMouseDown {
            keyPress.pressKey("v", priority: .regular, group: keyPressGroup)
        }
        return type == .otherMouseDown || type == .otherMouseUp
    }

    private func reenableEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        print("🖱️ Re-enabled middle mouse mapper tap")
    }
}
