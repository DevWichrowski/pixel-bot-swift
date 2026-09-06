import Foundation

/// Support cooldown is independent of the Healing group and starts at actual input dispatch.
final class SupportCooldown {
    static let shared = SupportCooldown()
    let hasteGroup = KeyPressRequestGroup()
    private let lock = NSLock()
    private var lastKeyDown: TimeInterval?
    private var shieldPending = false

    func isReady(at now: TimeInterval) -> Bool {
        lock.withLock { lastKeyDown.map { now - $0 >= 2 } ?? true }
    }

    func recordKeyDown(at now: TimeInterval) {
        lock.withLock { lastKeyDown = now }
    }

    func setShieldPending(_ pending: Bool) {
        lock.withLock { shieldPending = pending }
    }

    var mayRequestHaste: Bool { lock.withLock { !shieldPending } }
}

class AutoHaste {
    private let keyPress: any KeyPressServicing
    private let support: SupportCooldown
    private let lock = NSLock()
    private var pending = false
    private var nextCastUptime: TimeInterval = .infinity
    var enabled: Bool = false
    var hotkey: String = "x"

    init(keyPress: any KeyPressServicing = KeyPressService.shared, support: SupportCooldown = .shared) {
        self.keyPress = keyPress
        self.support = support
    }

    deinit { cancelPendingActions() }

    func toggle(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            lock.withLock { nextCastUptime = ProcessInfo.processInfo.systemUptime + nextDelay() }
        } else {
            cancelPendingActions()
        }
    }

    func checkAndCast() {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, support.mayRequestHaste, support.isReady(at: now) else { return }
        let shouldEnqueue = lock.withLock { () -> Bool in
            guard !pending, now >= nextCastUptime else { return false }
            pending = true
            return true
        }
        guard shouldEnqueue else { return }
        let accepted = keyPress.pressKey(hotkey, priority: .regular, group: support.hasteGroup,
                                        validUntil: now + 0.25, isValid: { [support] in
                                            support.mayRequestHaste && support.isReady(at: ProcessInfo.processInfo.systemUptime)
                                        }) { [weak self] event in
            guard let self else { return }
            if event.phase == .keyDown {
                self.support.recordKeyDown(at: event.timestamp)
                self.lock.withLock { self.nextCastUptime = event.timestamp + self.nextDelay() }
            }
            if [.keyUp, .cancelled, .failed].contains(event.phase) {
                self.lock.withLock { self.pending = false }
            }
        }
        if !accepted { lock.withLock { pending = false } }
    }

    private func nextDelay() -> TimeInterval {
        humanRandom(median: 32.0, spread: 0.06, min: 30.5, max: 38.0)
    }

    func cancelPendingActions() {
        keyPress.cancelPendingRequests(in: support.hasteGroup)
    }
}
