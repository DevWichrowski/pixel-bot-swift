import XCTest
import Carbon.HIToolbox
@testable import PixelBot

final class KeyPressPriorityTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValues: [String] = []

        func append(_ value: String) {
            lock.withLock { storedValues.append(value) }
        }

        var values: [String] {
            lock.withLock { storedValues }
        }
    }

    private final class LifecycleRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedEvents: [KeyPressLifecycleEvent] = []

        func append(_ event: KeyPressLifecycleEvent) {
            lock.withLock { storedEvents.append(event) }
        }

        var events: [KeyPressLifecycleEvent] {
            lock.withLock { storedEvents }
        }
    }

    private final class LogRecorder: DiagnosticLogging, @unchecked Sendable {
        private let lock = NSLock()
        private var storedKeyDownFields: [String: DiagnosticLogValue] = [:]
        let keyDown = DispatchSemaphore(value: 0)

        func log(_ event: String, fields: [String: DiagnosticLogValue]) {
            guard event == "input_keyDown" else { return }
            lock.withLock { storedKeyDownFields = fields }
            keyDown.signal()
        }

        var keyDownFields: [String: DiagnosticLogValue] {
            lock.withLock { storedKeyDownFields }
        }
    }

    private func it(_ description: String, body: () throws -> Void) rethrows {
        _ = description
        try body()
    }

    func testHealingBypassesRegularGate() {
        it("should start healing immediately through a regular post-keyUp gate") {
            let regularUp = DispatchSemaphore(value: 0)
            let healingDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if keyCode == CGKeyCode(kVK_F2), isKeyDown { healingDown.signal() }
                    return true
                },
                holdDurationProvider: { 0 },
                gapDurationProvider: nil,
                healingGapDurationProvider: { 0 },
                urgentGapDurationProvider: { 0 },
                regularGapDurationProvider: { 0.3 }
            )
            service.pressKey(
                "F1",
                priority: .regular,
                group: nil,
                validUntil: nil,
                lifecycle: { event in
                    if event.phase == .keyUp { regularUp.signal() }
                }
            )
            _ = regularUp.wait(timeout: .now() + 1)

            let startedAt = ProcessInfo.processInfo.systemUptime
            service.pressKey("F2", priority: .healing)
            _ = healingDown.wait(timeout: .now() + 1)
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            service.cancelAll()

            XCTAssertLessThan(elapsed, 0.1)
        }
    }

    func testHealingBypassesUrgentGate() {
        it("should start healing immediately through an urgent post-keyUp gate") {
            let urgentUp = DispatchSemaphore(value: 0)
            let healingDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if keyCode == CGKeyCode(kVK_F2), isKeyDown { healingDown.signal() }
                    return true
                },
                holdDurationProvider: { 0 },
                gapDurationProvider: nil,
                healingGapDurationProvider: { 0 },
                urgentGapDurationProvider: { 0.3 },
                regularGapDurationProvider: { 0 }
            )
            service.pressKey(
                "F1",
                priority: .urgent,
                group: nil,
                validUntil: nil,
                lifecycle: { event in
                    if event.phase == .keyUp { urgentUp.signal() }
                }
            )
            _ = urgentUp.wait(timeout: .now() + 1)

            let startedAt = ProcessInfo.processInfo.systemUptime
            service.pressKey("F2", priority: .healing)
            _ = healingDown.wait(timeout: .now() + 1)
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            service.cancelAll()

            XCTAssertLessThan(elapsed, 0.1)
        }
    }

    func testUrgentBypassesRegularGate() {
        it("should start urgent input immediately through a regular post-keyUp gate") {
            let regularUp = DispatchSemaphore(value: 0)
            let urgentDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if keyCode == CGKeyCode(kVK_F2), isKeyDown { urgentDown.signal() }
                    return true
                },
                holdDurationProvider: { 0 },
                gapDurationProvider: nil,
                healingGapDurationProvider: { 0 },
                urgentGapDurationProvider: { 0 },
                regularGapDurationProvider: { 0.3 }
            )
            service.pressKey(
                "F1",
                priority: .regular,
                group: nil,
                validUntil: nil,
                lifecycle: { event in
                    if event.phase == .keyUp { regularUp.signal() }
                }
            )
            _ = regularUp.wait(timeout: .now() + 1)

            let startedAt = ProcessInfo.processInfo.systemUptime
            service.pressKey("F2", priority: .urgent)
            _ = urgentDown.wait(timeout: .now() + 1)
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            service.cancelAll()

            XCTAssertLessThan(elapsed, 0.1)
        }
    }

    func testHealingWaitsForActiveKeyUp() {
        it("should start healing after the active keyUp without interrupting its keyDown") {
            let recorder = Recorder()
            let firstDown = DispatchSemaphore(value: 0)
            let healingDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    recorder.append("\(keyCode):\(isKeyDown ? "down" : "up")")
                    if keyCode == CGKeyCode(kVK_F1), isKeyDown { firstDown.signal() }
                    if keyCode == CGKeyCode(kVK_F2), isKeyDown { healingDown.signal() }
                    return true
                },
                healingHoldDurationProvider: { 0 },
                urgentHoldDurationProvider: { 0 },
                regularHoldDurationProvider: { 0.05 },
                healingGapDurationProvider: { 0 },
                urgentGapDurationProvider: { 0 },
                regularGapDurationProvider: { 0.3 }
            )

            service.pressKey("F1", priority: .regular)
            _ = firstDown.wait(timeout: .now() + 1)
            service.pressKey("F2", priority: .healing)
            _ = healingDown.wait(timeout: .now() + 1)
            let events = Array(recorder.values.prefix(3))
            service.cancelAll()

            XCTAssertEqual(events, [
                "\(CGKeyCode(kVK_F1)):down",
                "\(CGKeyCode(kVK_F1)):up",
                "\(CGKeyCode(kVK_F2)):down",
            ])
        }
    }

    func testPriorityAndFIFOOrdering() {
        it("should preserve FIFO within healing urgent and regular priority queues") {
            let recorder = Recorder()
            let keyDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if isKeyDown {
                        recorder.append("\(keyCode)")
                        keyDown.signal()
                    }
                    return true
                },
                healingHoldDurationProvider: { 0 },
                urgentHoldDurationProvider: { 0 },
                regularHoldDurationProvider: { 0.05 },
                healingGapDurationProvider: { 0 },
                urgentGapDurationProvider: { 0 },
                regularGapDurationProvider: { 0 }
            )

            service.pressKey("F1", priority: .regular)
            _ = keyDown.wait(timeout: .now() + 1)
            service.pressKey("F5", priority: .regular)
            service.pressKey("F2", priority: .healing)
            service.pressKey("F3", priority: .healing)
            service.pressKey("F4", priority: .urgent)
            for _ in 0..<4 { _ = keyDown.wait(timeout: .now() + 1) }
            service.cancelAll()

            XCTAssertEqual(recorder.values, [
                "\(CGKeyCode(kVK_F1))",
                "\(CGKeyCode(kVK_F2))",
                "\(CGKeyCode(kVK_F3))",
                "\(CGKeyCode(kVK_F4))",
                "\(CGKeyCode(kVK_F5))",
            ])
        }
    }

    func testPriorityTimingProviderSelection() {
        it("should sample the matching hold and gap provider once per action") {
            let recorder = Recorder()
            let keyUp = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { _, isKeyDown in
                    if !isKeyDown { keyUp.signal() }
                    return true
                },
                healingHoldDurationProvider: { recorder.append("healing-hold"); return 0 },
                urgentHoldDurationProvider: { recorder.append("urgent-hold"); return 0 },
                regularHoldDurationProvider: { recorder.append("regular-hold"); return 0 },
                healingGapDurationProvider: { recorder.append("healing-gap"); return 0 },
                urgentGapDurationProvider: { recorder.append("urgent-gap"); return 0 },
                regularGapDurationProvider: { recorder.append("regular-gap"); return 0 }
            )

            service.pressKey("F1", priority: .healing)
            _ = keyUp.wait(timeout: .now() + 1)
            service.pressKey("F2", priority: .urgent)
            _ = keyUp.wait(timeout: .now() + 1)
            service.pressKey("F3", priority: .regular)
            _ = keyUp.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(recorder.values, [
                "healing-hold", "healing-gap",
                "urgent-hold", "urgent-gap",
                "regular-hold", "regular-gap",
            ])
        }
    }

    func testDefaultTimingBounds() {
        it("should keep every default hold and gap sample inside its priority bounds") {
            let samples = (0..<200).flatMap { _ -> [Bool] in
                let healingHold = KeyPressService.defaultHoldDuration(for: .healing)
                let urgentHold = KeyPressService.defaultHoldDuration(for: .urgent)
                let regularHold = KeyPressService.defaultHoldDuration(for: .regular)
                let healingGap = KeyPressService.defaultGapDuration(for: .healing)
                let urgentGap = KeyPressService.defaultGapDuration(for: .urgent)
                let regularGap = KeyPressService.defaultGapDuration(for: .regular)
                return [
                    (0.040...0.060).contains(healingHold),
                    (0.040...0.075).contains(urgentHold),
                    (0.040...0.100).contains(regularHold),
                    (0.008...0.025).contains(healingGap),
                    (0.015...0.045).contains(urgentGap),
                    (0.030...0.090).contains(regularGap),
                ]
            }

            XCTAssertTrue(samples.allSatisfy { $0 })
        }
    }

    func testUrgentCompatibilityOverload() {
        it("should map the urgent Bool overload to urgent priority") {
            let lifecycle = LifecycleRecorder()
            let keyDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { _, _ in true },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 }
            )

            service.pressKey(
                "F1",
                urgent: true,
                group: nil,
                validUntil: nil,
                lifecycle: { event in
                    lifecycle.append(event)
                    if event.phase == .keyDown { keyDown.signal() }
                }
            )
            _ = keyDown.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(lifecycle.events.first { $0.phase == .keyDown }?.priority, .urgent)
        }
    }

    func testLegacyTimingProviderShim() {
        it("should use legacy timing providers for every priority") {
            let recorder = Recorder()
            let keyUp = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { _, isKeyDown in
                    if !isKeyDown { keyUp.signal() }
                    return true
                },
                holdDurationProvider: { recorder.append("hold"); return 0 },
                gapDurationProvider: { recorder.append("gap"); return 0 }
            )

            for priority in [KeyPressPriority.healing, .urgent, .regular] {
                service.pressKey("F1", priority: priority)
                _ = keyUp.wait(timeout: .now() + 1)
            }
            service.cancelAll()

            XCTAssertEqual(recorder.values, ["hold", "gap", "hold", "gap", "hold", "gap"])
        }
    }

    func testCancelAllAfterKeyUp() {
        it("should not emit cancelled after a completed keyUp") {
            let lifecycle = LifecycleRecorder()
            let keyUp = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { _, _ in true },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0.3 }
            )

            service.pressKey(
                "F1",
                priority: .regular,
                group: nil,
                validUntil: nil,
                lifecycle: { event in
                    lifecycle.append(event)
                    if event.phase == .keyUp { keyUp.signal() }
                }
            )
            _ = keyUp.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(lifecycle.events.map(\.phase), [.queued, .keyDown, .keyUp])
        }
    }

    func testDeadlineBoundary() {
        it("should expire a request when validUntil is exactly at the current boundary") {
            let lifecycle = LifecycleRecorder()
            let cancelled = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { _, _ in true },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 }
            )

            service.pressKey(
                "F1",
                priority: .healing,
                group: nil,
                validUntil: ProcessInfo.processInfo.systemUptime,
                lifecycle: { event in
                    lifecycle.append(event)
                    if event.phase == .cancelled { cancelled.signal() }
                }
            )
            _ = cancelled.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(lifecycle.events.map(\.phase), [.queued, .cancelled])
        }
    }

    func testLifecycleAndDiagnosticMetadata() {
        it("should include priority and deadline metadata at keyDown and in its diagnostic log") {
            let lifecycle = LifecycleRecorder()
            let logger = LogRecorder()
            let service = KeyPressService(
                eventPoster: { _, _ in true },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 },
                diagnosticLogger: logger
            )

            service.pressKey(
                "F1",
                priority: .healing,
                group: nil,
                validUntil: ProcessInfo.processInfo.systemUptime + 0.25,
                lifecycle: { event in lifecycle.append(event) }
            )
            _ = logger.keyDown.wait(timeout: .now() + 1)
            let event = lifecycle.events.first { $0.phase == .keyDown }
            let fields = logger.keyDownFields
            let validityRemainingMs = (event?.validityRemaining ?? 0) * 1_000
            let frameToKeyDownMs = fields.doubleValue(for: "frameToKeyDownMs")
            service.cancelAll()

            XCTAssertTrue(
                event?.priority == .healing
                    && (event?.validityRemaining ?? 0) > 0
                    && fields.stringValue(for: "priority") == "healing"
                    && (fields.doubleValue(for: "validityRemainingMs") ?? 0) > 0
                    && abs((frameToKeyDownMs ?? -1) - max(0, 250 - validityRemainingMs)) < 0.001
            )
        }
    }
}

private extension Dictionary where Key == String, Value == DiagnosticLogValue {
    func stringValue(for key: String) -> String? {
        guard case .string(let value) = self[key] else { return nil }
        return value
    }

    func doubleValue(for key: String) -> Double? {
        guard case .double(let value) = self[key] else { return nil }
        return value
    }
}
