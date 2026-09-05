import XCTest
import Carbon.HIToolbox
@testable import PixelBot

final class InputFeatureTests: XCTestCase {
    private final class EventRecorder {
        private let lock = NSLock()
        private var storedEvents: [String] = []

        func record(keyCode: CGKeyCode, isKeyDown: Bool) {
            lock.lock()
            storedEvents.append("\(keyCode):\(isKeyDown ? "down" : "up")")
            lock.unlock()
        }

        var events: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storedEvents
        }
    }

    private final class PhaseRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedPhases: [KeyPressLifecyclePhase] = []

        func record(_ phase: KeyPressLifecyclePhase) {
            lock.withLock { storedPhases.append(phase) }
        }

        var phases: [KeyPressLifecyclePhase] {
            lock.withLock { storedPhases }
        }
    }

    private final class RecordingKeyPressService: KeyPressServicing {
        private let lock = NSLock()
        private var storedKeys: [String] = []
        private var storedPriorities: [KeyPressPriority] = []
        private var storedCancellationCount = 0
        var acceptsRequests = true

        @discardableResult
        func pressKey(
            _ key: String,
            priority: KeyPressPriority,
            group: KeyPressRequestGroup?,
            validUntil: TimeInterval?,
            lifecycle: KeyPressLifecycleHandler?
        ) -> Bool {
            guard acceptsRequests else { return false }
            _ = validUntil
            let requestID = UUID()
            let timestamp = ProcessInfo.processInfo.systemUptime
            lifecycle?(KeyPressLifecycleEvent(
                requestID: requestID,
                key: key,
                priority: priority,
                phase: .queued,
                timestamp: timestamp,
                queueWait: 0,
                validityRemaining: validUntil.map { max(0, $0 - timestamp) }
            ))
            lock.lock()
            storedKeys.append(key)
            storedPriorities.append(priority)
            lock.unlock()
            lifecycle?(KeyPressLifecycleEvent(
                requestID: requestID,
                key: key,
                priority: priority,
                phase: .keyDown,
                timestamp: timestamp,
                queueWait: 0,
                validityRemaining: validUntil.map { max(0, $0 - timestamp) }
            ))
            lifecycle?(KeyPressLifecycleEvent(
                requestID: requestID,
                key: key,
                priority: priority,
                phase: .keyUp,
                timestamp: timestamp,
                queueWait: 0,
                validityRemaining: validUntil.map { max(0, $0 - timestamp) }
            ))
            return true
        }

        func cancelPendingRequests(in group: KeyPressRequestGroup) {
            lock.lock()
            storedCancellationCount += 1
            lock.unlock()
        }

        var keys: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storedKeys
        }

        var cancellationCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedCancellationCount
        }

        var priorities: [KeyPressPriority] {
            lock.lock()
            defer { lock.unlock() }
            return storedPriorities
        }
    }

    private final class PendingKeyPressService: KeyPressServicing {
        private struct Request {
            let id: UUID
            let key: String
            let priority: KeyPressPriority
            let group: KeyPressRequestGroup?
            let validUntil: TimeInterval?
            let lifecycle: KeyPressLifecycleHandler?
        }

        private let lock = NSLock()
        private var requests: [Request] = []

        @discardableResult
        func pressKey(
            _ key: String,
            priority: KeyPressPriority,
            group: KeyPressRequestGroup?,
            validUntil: TimeInterval?,
            lifecycle: KeyPressLifecycleHandler?
        ) -> Bool {
            let request = Request(
                id: UUID(),
                key: key,
                priority: priority,
                group: group,
                validUntil: validUntil,
                lifecycle: lifecycle
            )
            lock.withLock { requests.append(request) }
            lifecycle?(event(for: request, phase: .queued))
            return true
        }

        func cancelPendingRequests(in group: KeyPressRequestGroup) {
            let cancelled = lock.withLock { () -> [Request] in
                let matches = requests.filter { $0.group == group }
                requests.removeAll { $0.group == group }
                return matches
            }
            cancelled.forEach { $0.lifecycle?(event(for: $0, phase: .cancelled)) }
        }

        var pendingKeys: [String] {
            lock.withLock { requests.map(\.key) }
        }

        func completeFirst(at timestamp: TimeInterval) {
            guard let request = lock.withLock({ requests.first }) else { return }
            request.lifecycle?(event(for: request, phase: .keyDown, timestamp: timestamp))
            request.lifecycle?(event(for: request, phase: .keyUp, timestamp: timestamp))
            lock.withLock { requests.removeAll { $0.id == request.id } }
        }

        private func event(
            for request: Request,
            phase: KeyPressLifecyclePhase,
            timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
        ) -> KeyPressLifecycleEvent {
            return KeyPressLifecycleEvent(
                requestID: request.id,
                key: request.key,
                priority: request.priority,
                phase: phase,
                timestamp: timestamp,
                queueWait: 0,
                validityRemaining: request.validUntil.map { max(0, $0 - timestamp) }
            )
        }
    }

    private func it(_ description: String, body: () throws -> Void) rethrows {
        _ = description
        try body()
    }

    private func waitForQueue(_ queue: DispatchQueue, after delay: TimeInterval) {
        let semaphore = DispatchSemaphore(value: 0)
        queue.asyncAfter(deadline: .now() + delay) {
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + delay + 1)
    }

    func testCancelRemovesPendingRequestBeforeKeyDown() {
        it("should cancel a pending request before keyDown") {
            let recorder = EventRecorder()
            let firstKeyDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    recorder.record(keyCode: keyCode, isKeyDown: isKeyDown)
                    if keyCode == CGKeyCode(kVK_F1), isKeyDown {
                        firstKeyDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 1 },
                gapDurationProvider: { 0 }
            )

            service.pressKey("F1")
            _ = firstKeyDown.wait(timeout: .now() + 1)
            service.pressKey("F2")
            service.cancelAll()

            XCTAssertEqual(
                recorder.events.filter { $0.hasSuffix(":down") },
                ["\(CGKeyCode(kVK_F1)):down"]
            )
        }
    }

    func testSuccessfulInputLifecycle() {
        it("should report queued keyDown and keyUp for a successful input") {
            let recorder = PhaseRecorder()
            let keyUp = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { _, _ in true },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 }
            )

            service.pressKey(
                "F1",
                urgent: false,
                group: nil,
                validUntil: nil,
                lifecycle: { event in
                    recorder.record(event.phase)
                    if event.phase == .keyUp {
                        keyUp.signal()
                    }
                }
            )
            _ = keyUp.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(recorder.phases, [.queued, .keyDown, .keyUp])
        }
    }

    func testCancelReleasesActiveKey() {
        it("should guarantee keyUp after cancellation") {
            let recorder = EventRecorder()
            let keyDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    recorder.record(keyCode: keyCode, isKeyDown: isKeyDown)
                    if isKeyDown {
                        keyDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 1 },
                gapDurationProvider: { 0 }
            )

            service.pressKey("F1")
            _ = keyDown.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(
                recorder.events,
                ["\(CGKeyCode(kVK_F1)):down", "\(CGKeyCode(kVK_F1)):up"]
            )
        }
    }

    func testUrgentRequestPrecedesRegularPendingRequest() {
        it("should prioritize urgent pending input without interrupting the active key") {
            let recorder = EventRecorder()
            let keyDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    recorder.record(keyCode: keyCode, isKeyDown: isKeyDown)
                    if isKeyDown {
                        keyDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0.1 },
                gapDurationProvider: { 0 }
            )

            service.pressKey("F1")
            _ = keyDown.wait(timeout: .now() + 1)
            service.pressKey("F2")
            service.pressKey("F3", urgent: true)
            _ = keyDown.wait(timeout: .now() + 1)
            _ = keyDown.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(
                recorder.events.filter { $0.hasSuffix(":down") },
                [
                    "\(CGKeyCode(kVK_F1)):down",
                    "\(CGKeyCode(kVK_F3)):down",
                    "\(CGKeyCode(kVK_F2)):down",
                ]
            )
        }
    }

    func testGroupCancellationPreservesActiveKey() {
        it("should cancel only pending requests in one feature group") {
            let recorder = EventRecorder()
            let keyDown = DispatchSemaphore(value: 0)
            let canceledGroup = KeyPressRequestGroup()
            let preservedGroup = KeyPressRequestGroup()
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    recorder.record(keyCode: keyCode, isKeyDown: isKeyDown)
                    if isKeyDown {
                        keyDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0.1 },
                gapDurationProvider: { 0 }
            )

            service.pressKey("F1", urgent: false, group: canceledGroup)
            _ = keyDown.wait(timeout: .now() + 1)
            service.pressKey("F2", urgent: false, group: canceledGroup)
            service.pressKey("F3", urgent: false, group: preservedGroup)
            service.cancelPendingRequests(in: canceledGroup)
            _ = keyDown.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(
                recorder.events.filter { $0.hasSuffix(":down") },
                ["\(CGKeyCode(kVK_F1)):down", "\(CGKeyCode(kVK_F3)):down"]
            )
        }
    }

    func testKeyUpRetry() {
        it("should retry keyUp after a temporary posting failure") {
            let recorder = EventRecorder()
            let keyDown = DispatchSemaphore(value: 0)
            let successfulKeyUp = DispatchSemaphore(value: 0)
            var shouldFailKeyUp = true
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    recorder.record(keyCode: keyCode, isKeyDown: isKeyDown)
                    if isKeyDown {
                        keyDown.signal()
                        return true
                    }
                    if shouldFailKeyUp {
                        shouldFailKeyUp = false
                        return false
                    }
                    successfulKeyUp.signal()
                    return true
                },
                holdDurationProvider: { 1 },
                gapDurationProvider: { 0 },
                keyUpRetryInterval: 0.001
            )

            service.pressKey("F1")
            _ = keyDown.wait(timeout: .now() + 1)
            service.cancelAll()
            _ = successfulKeyUp.wait(timeout: .now() + 1)

            XCTAssertEqual(
                recorder.events,
                [
                    "\(CGKeyCode(kVK_F1)):down",
                    "\(CGKeyCode(kVK_F1)):up",
                    "\(CGKeyCode(kVK_F1)):up",
                ]
            )
        }
    }

    func testResumeAllowsInputAfterCancel() {
        it("should accept new requests only after resume") {
            let service = KeyPressService(
                eventPoster: { _, _ in true },
                holdDurationProvider: { 1 },
                gapDurationProvider: { 0 }
            )

            service.cancelAll()
            let whileStopped = service.pressKey("F1")
            service.resume()
            let afterResume = service.pressKey("F1")
            service.cancelAll()

            XCTAssertEqual([whileStopped, afterResume], [false, true])
        }
    }

    func testFirstHealingDecisionHasNoReactionDelay() {
        it("should send the first valid healing decision immediately") {
            let keyDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if keyCode == CGKeyCode(kVK_F1), isKeyDown {
                        keyDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 }
            )
            let healer = AutoHealer(keyPress: service)
            healer.setMaxHP(100)
            healer.criticalHeal.enabled = false

            healer.checkAndHeal(currentHP: 60)
            let result = keyDown.wait(timeout: .now() + 0.1)
            service.cancelAll()

            XCTAssertEqual(result, .success)
        }
    }

    func testHealingCooldownStartsAtKeyDown() {
        it("should keep normal and critical keyDown events at least one second apart") {
            let lock = NSLock()
            var keyDownTimes: [TimeInterval] = []
            let keyDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if [CGKeyCode(kVK_F1), CGKeyCode(kVK_F2)].contains(keyCode), isKeyDown {
                        lock.withLock {
                            keyDownTimes.append(ProcessInfo.processInfo.systemUptime)
                        }
                        keyDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 }
            )
            let healer = AutoHealer(keyPress: service)
            healer.setMaxHP(100)

            healer.checkAndHeal(currentHP: 60)
            _ = keyDown.wait(timeout: .now() + 1)
            Thread.sleep(forTimeInterval: 1.02)
            healer.checkAndHeal(currentHP: 40)
            _ = keyDown.wait(timeout: .now() + 1)
            let interval = lock.withLock { keyDownTimes[1] - keyDownTimes[0] }
            service.cancelAll()

            XCTAssertGreaterThanOrEqual(interval, 1.0)
        }
    }

    func testQueueWaitDoesNotShortenHealingCooldown() {
        it("should measure the healing cooldown from keyDown instead of enqueue time") {
            let blockerDown = DispatchSemaphore(value: 0)
            let healingDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if keyCode == CGKeyCode(kVK_F9), isKeyDown {
                        blockerDown.signal()
                    }
                    if keyCode == CGKeyCode(kVK_F1), isKeyDown {
                        healingDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0.25 },
                gapDurationProvider: { 0 }
            )
            let healer = AutoHealer(keyPress: service)
            healer.setMaxHP(100)

            service.pressKey("F9")
            _ = blockerDown.wait(timeout: .now() + 1)
            let enqueuedAt = ProcessInfo.processInfo.systemUptime
            healer.checkAndHeal(currentHP: 60)
            _ = healingDown.wait(timeout: .now() + 1)
            let queueWait = ProcessInfo.processInfo.systemUptime - enqueuedAt
            Thread.sleep(forTimeInterval: max(0, 1.02 - queueWait))
            let secondDecision = healer.checkAndHeal(currentHP: 40)
            let remaining = healer.healingCooldownRemaining
            service.cancelAll()

            XCTAssertTrue(queueWait >= 0.20 && secondDecision == nil && remaining > 0)
        }
    }

    func testCriticalReplacesPendingNormalHealing() {
        it("should replace one pending normal heal with critical without interrupting the active key") {
            let lock = NSLock()
            var healingKeys: [CGKeyCode] = []
            let blockerDown = DispatchSemaphore(value: 0)
            let healingDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    guard isKeyDown else { return true }
                    if keyCode == CGKeyCode(kVK_F9) {
                        blockerDown.signal()
                    } else if [CGKeyCode(kVK_F1), CGKeyCode(kVK_F2)].contains(keyCode) {
                        lock.withLock { healingKeys.append(keyCode) }
                        healingDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0.15 },
                gapDurationProvider: { 0 }
            )
            let healer = AutoHealer(keyPress: service)
            healer.setMaxHP(100)

            service.pressKey("F9")
            _ = blockerDown.wait(timeout: .now() + 1)
            healer.checkAndHeal(currentHP: 60)
            healer.checkAndHeal(currentHP: 40)
            _ = healingDown.wait(timeout: .now() + 1)
            service.cancelAll()

            XCTAssertEqual(lock.withLock { healingKeys }, [CGKeyCode(kVK_F2)])
        }
    }

    func testHealingDoesNotQueueDuplicates() {
        it("should keep at most one pending healing spell") {
            let lock = NSLock()
            var healingKeyDownCount = 0
            let blockerDown = DispatchSemaphore(value: 0)
            let healingDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    guard isKeyDown else { return true }
                    if keyCode == CGKeyCode(kVK_F9) {
                        blockerDown.signal()
                    } else if keyCode == CGKeyCode(kVK_F1) {
                        lock.withLock { healingKeyDownCount += 1 }
                        healingDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0.15 },
                gapDurationProvider: { 0 }
            )
            let healer = AutoHealer(keyPress: service)
            healer.setMaxHP(100)
            healer.criticalHeal.enabled = false

            service.pressKey("F9")
            _ = blockerDown.wait(timeout: .now() + 1)
            for _ in 0..<5 {
                healer.checkAndHeal(currentHP: 60)
            }
            _ = healingDown.wait(timeout: .now() + 1)
            Thread.sleep(forTimeInterval: 0.05)
            service.cancelAll()

            XCTAssertEqual(lock.withLock { healingKeyDownCount }, 1)
        }
    }

    func testFailedHealingInputDoesNotStartCooldown() {
        it("should allow an immediate retry when healing keyDown fails") {
            let lock = NSLock()
            var shouldFail = true
            let failedAttempt = DispatchSemaphore(value: 0)
            let successfulAttempt = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    guard keyCode == CGKeyCode(kVK_F1), isKeyDown else { return true }
                    return lock.withLock {
                        if shouldFail {
                            shouldFail = false
                            failedAttempt.signal()
                            return false
                        }
                        successfulAttempt.signal()
                        return true
                    }
                },
                holdDurationProvider: { 0 },
                gapDurationProvider: { 0 }
            )
            let healer = AutoHealer(keyPress: service)
            healer.setMaxHP(100)
            healer.criticalHeal.enabled = false

            healer.checkAndHeal(currentHP: 60)
            _ = failedAttempt.wait(timeout: .now() + 1)
            Thread.sleep(forTimeInterval: 0.01)
            healer.checkAndHeal(currentHP: 60)
            let result = successfulAttempt.wait(timeout: .now() + 0.1)
            service.cancelAll()

            XCTAssertEqual(result, .success)
        }
    }

    func testCancelledHealingInputDoesNotStartCooldown() {
        it("should allow an immediate retry when pending healing input is cancelled") {
            let blockerDown = DispatchSemaphore(value: 0)
            let healingDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if keyCode == CGKeyCode(kVK_F9), isKeyDown {
                        blockerDown.signal()
                    }
                    if keyCode == CGKeyCode(kVK_F1), isKeyDown {
                        healingDown.signal()
                    }
                    return true
                },
                holdDurationProvider: { 0.15 },
                gapDurationProvider: { 0 }
            )
            let healer = AutoHealer(keyPress: service)
            healer.setMaxHP(100)
            healer.criticalHeal.enabled = false

            service.pressKey("F9")
            _ = blockerDown.wait(timeout: .now() + 1)
            healer.checkAndHeal(currentHP: 60)
            healer.cancelPendingHealing()
            Thread.sleep(forTimeInterval: 0.2)
            healer.checkAndHeal(currentHP: 60)
            let result = healingDown.wait(timeout: .now() + 0.3)
            service.cancelAll()

            XCTAssertEqual(result, .success)
        }
    }

    func testExpiredPendingInputIsNotSent() {
        it("should cancel queued healing input after its HP reading becomes stale") {
            let lock = NSLock()
            let phaseRecorder = PhaseRecorder()
            var healingKeyDownCount = 0
            let blockerDown = DispatchSemaphore(value: 0)
            let service = KeyPressService(
                eventPoster: { keyCode, isKeyDown in
                    if keyCode == CGKeyCode(kVK_F9), isKeyDown {
                        blockerDown.signal()
                    }
                    if keyCode == CGKeyCode(kVK_F1), isKeyDown {
                        lock.withLock { healingKeyDownCount += 1 }
                    }
                    return true
                },
                holdDurationProvider: { 0.15 },
                gapDurationProvider: { 0 }
            )

            service.pressKey("F9")
            _ = blockerDown.wait(timeout: .now() + 1)
            service.pressKey(
                "F1",
                urgent: true,
                group: KeyPressRequestGroup(),
                validUntil: ProcessInfo.processInfo.systemUptime + 0.03,
                lifecycle: { event in
                    phaseRecorder.record(event.phase)
                }
            )
            Thread.sleep(forTimeInterval: 0.2)
            service.cancelAll()

            XCTAssertTrue(lock.withLock {
                phaseRecorder.phases == [.queued, .cancelled] && healingKeyDownCount == 0
            })
        }
    }

    func testSpiritPotionImmediateEnqueue() {
        it("should enqueue the critical spell and Spirit Potion synchronously") {
            let keyPress = RecordingKeyPressService()
            let actionQueue = DispatchQueue(label: "InputFeatureTests.spirit")
            let healer = AutoHealer(
                keyPress: keyPress,
                delayedActionQueue: actionQueue,
                reactionDelayOverride: { 0 },
                interActionDelayOverride: { 0.02 }
            )
            healer.setMaxHP(100)
            healer.setMaxMana(100)
            healer.spiritPotionHeal = true

            _ = healer.checkSpiritPotionHeal(currentHP: 30, currentMana: 100)
            _ = healer.checkSpiritPotionHeal(currentHP: 30, currentMana: 100)
            healer.spiritPotionHeal = false
            XCTAssertEqual(keyPress.keys, ["F2", "F3"])
        }
    }

    func testHealerInputPriorities() {
        it("should map HP actions to healing and mana restore to urgent") {
            let keyPress = RecordingKeyPressService()

            let normal = AutoHealer(keyPress: keyPress)
            normal.setMaxHP(100)
            normal.criticalHeal.enabled = false
            normal.checkAndHeal(currentHP: 60)

            let critical = AutoHealer(keyPress: keyPress)
            critical.setMaxHP(100)
            critical.checkAndHeal(currentHP: 40)

            let criticalPotion = AutoHealer(keyPress: keyPress)
            criticalPotion.setMaxHP(100)
            criticalPotion.checkCriticalPotionHeal(currentHP: 40)

            let spiritPotion = AutoHealer(keyPress: keyPress)
            spiritPotion.setMaxHP(100)
            spiritPotion.spiritPotionHeal = true
            spiritPotion.criticalHeal.enabled = false
            _ = spiritPotion.checkSpiritPotionHeal(currentHP: 30)

            let mana = AutoHealer(keyPress: keyPress)
            mana.setMaxMana(100)
            mana.checkAndRestoreMana(currentMana: 40)

            XCTAssertEqual(
                keyPress.priorities,
                [.healing, .healing, .healing, .healing, .urgent]
            )
        }
    }

    func testRejectedManaInputReportsFailure() {
        it("should report mana restoration only when the request is accepted") {
            let keyPress = RecordingKeyPressService()
            keyPress.acceptsRequests = false
            let healer = AutoHealer(keyPress: keyPress)
            healer.setMaxMana(100)

            let restored = healer.checkAndRestoreMana(currentMana: 40)

            XCTAssertFalse(restored)
        }
    }

    func testHPPotionReplacesPendingManaPotion() {
        it("should replace a pending mana potion with an HP potion") {
            let keyPress = PendingKeyPressService()
            let healer = AutoHealer(keyPress: keyPress)
            healer.setMaxHP(100)
            healer.setMaxMana(100)

            healer.checkAndRestoreMana(currentMana: 40)
            healer.checkCriticalPotionHeal(currentHP: 40)

            XCTAssertEqual(keyPress.pendingKeys, ["F2"])
        }
    }

    func testManaPotionDoesNotReplacePendingHPPotion() {
        it("should preserve a pending HP potion when mana is low") {
            let keyPress = PendingKeyPressService()
            let healer = AutoHealer(keyPress: keyPress)
            healer.setMaxHP(100)
            healer.setMaxMana(100)

            healer.checkCriticalPotionHeal(currentHP: 40)
            let restored = healer.checkAndRestoreMana(currentMana: 40)

            XCTAssertTrue(keyPress.pendingKeys == ["F2"] && !restored)
        }
    }

    func testPotionCancellationBeforeKeyDownDoesNotStartCooldown() {
        it("should allow a potion retry after cancellation before keyDown") {
            let keyPress = PendingKeyPressService()
            let healer = AutoHealer(keyPress: keyPress)
            healer.setMaxMana(100)

            let first = healer.checkAndRestoreMana(currentMana: 40)
            healer.cancelPendingActions()
            let second = healer.checkAndRestoreMana(currentMana: 40)

            XCTAssertTrue(first && second && keyPress.pendingKeys == ["F4"])
        }
    }

    func testPotionCooldownStartsAtKeyDown() {
        it("should measure the shared potion cooldown from keyDown") {
            var uptime = 10.0
            let keyPress = PendingKeyPressService()
            let healer = AutoHealer(
                keyPress: keyPress,
                uptimeProvider: { uptime }
            )
            healer.setMaxMana(100)

            healer.checkAndRestoreMana(currentMana: 40)
            uptime = 20.0
            keyPress.completeFirst(at: uptime)
            uptime = 20.49
            let beforeMinimum = healer.isPotionOnCooldown
            uptime = 20.86
            let afterMaximum = healer.isPotionOnCooldown

            XCTAssertEqual([beforeMinimum, afterMaximum], [true, false])
        }
    }

    func testInvalidHPCancelsOnlyHPDependentRequests() {
        it("should cancel spell and HP potion requests without cancelling mana") {
            let keyPress = PendingKeyPressService()
            let healer = AutoHealer(keyPress: keyPress)
            healer.setMaxHP(100)
            healer.setMaxMana(100)
            healer.spiritPotionHeal = true

            _ = healer.checkSpiritPotionHeal(currentHP: 30)
            healer.cancelPendingHPDependentActions()
            healer.checkAndRestoreMana(currentMana: 40)
            healer.cancelPendingHPDependentActions()

            XCTAssertEqual(keyPress.pendingKeys, ["F4"])
        }
    }

    func testAutoEaterCancellation() {
        it("should cancel the second food press when Auto Eater is disabled") {
            let keyPress = RecordingKeyPressService()
            let actionQueue = DispatchQueue(label: "InputFeatureTests.eater")
            let eater = AutoEater(
                keyPress: keyPress,
                delayedActionQueue: actionQueue,
                secondPressDelayOverride: { 0.02 }
            )
            eater.toggle(true)

            eater.eatNow()
            eater.toggle(false)
            waitForQueue(actionQueue, after: 0.05)

            XCTAssertEqual(keyPress.keys, ["]"])
        }
    }

    func testAutoHasteCancellation() {
        it("should cancel pending Auto Haste key requests when disabled") {
            let keyPress = RecordingKeyPressService()
            let haste = AutoHaste(keyPress: keyPress)

            haste.toggle(false)

            XCTAssertEqual(keyPress.cancellationCount, 1)
        }
    }

    func testAutoSkinnerCancellation() {
        it("should cancel skinning when Auto Skinner is disabled") {
            let keyPress = RecordingKeyPressService()
            let actionQueue = DispatchQueue(label: "InputFeatureTests.skinner")
            let skinner = AutoSkinner(
                keyPress: keyPress,
                delayedActionQueue: actionQueue,
                skinningDelayOverride: { 0.02 }
            )
            skinner.toggle(true)

            skinner.performSkinning()
            skinner.toggle(false)
            waitForQueue(actionQueue, after: 0.05)

            XCTAssertEqual(keyPress.keys, [])
        }
    }

    func testAutoLootCancellation() {
        it("should cancel delayed loot when Auto Combo is disabled") {
            let keyPress = RecordingKeyPressService()
            let actionQueue = DispatchQueue(label: "InputFeatureTests.loot")
            let combo = AutoCombo(
                keyPress: keyPress,
                delayedActionQueue: actionQueue,
                lootDelayOverride: { 0.02 }
            )
            combo.enabled = true
            combo.toggleActive()
            combo.toggleActive()

            combo.toggle(false)
            waitForQueue(actionQueue, after: 0.05)

            XCTAssertEqual(keyPress.keys, [])
        }
    }

    func testMiddleMouseDownMapsToV() {
        it("should map middle mouse down to V") {
            let keyPress = RecordingKeyPressService()
            let mapper = MiddleMouseKeyMapper(keyPress: keyPress)

            mapper.handleMouseEvent(type: .otherMouseDown, buttonNumber: 2)

            XCTAssertEqual(keyPress.keys, ["v"])
        }
    }

    func testMiddleMouseDownAndUpAreSuppressed() {
        it("should suppress middle mouse down and up") {
            let keyPress = RecordingKeyPressService()
            let mapper = MiddleMouseKeyMapper(keyPress: keyPress)

            let down = mapper.handleMouseEvent(type: .otherMouseDown, buttonNumber: 2)
            let up = mapper.handleMouseEvent(type: .otherMouseUp, buttonNumber: 2)

            XCTAssertEqual([down, up], [true, true])
        }
    }

    func testOtherMouseButtonsPassThrough() {
        it("should pass through other additional mouse buttons") {
            let keyPress = RecordingKeyPressService()
            let mapper = MiddleMouseKeyMapper(keyPress: keyPress)

            let down = mapper.handleMouseEvent(type: .otherMouseDown, buttonNumber: 3)
            let up = mapper.handleMouseEvent(type: .otherMouseUp, buttonNumber: 3)

            XCTAssertEqual([down, up], [false, false])
        }
    }

    func testMiddleMouseUpDoesNotSendAnotherV() {
        it("should send V only once for a complete middle mouse click") {
            let keyPress = RecordingKeyPressService()
            let mapper = MiddleMouseKeyMapper(keyPress: keyPress)

            mapper.handleMouseEvent(type: .otherMouseDown, buttonNumber: 2)
            mapper.handleMouseEvent(type: .otherMouseUp, buttonNumber: 2)

            XCTAssertEqual(keyPress.keys, ["v"])
        }
    }
}
