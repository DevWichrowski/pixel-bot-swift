import Foundation

/// Observation confirms activation; posting the hotkey only records an attempt.
final class AutoMagicShield {
    private let keyPress: any KeyPressServicing
    private let support: SupportCooldown
    private let group = KeyPressRequestGroup()
    private let lock = NSLock()
    private var pending: UUID?
    private var lastAttempt: TimeInterval = -.infinity
    private var previousHP: TimeInterval?
    private var previousShield: TimeInterval?
    private var hpConfirmations = 0
    private var inactiveConfirmations = 0
    var enabled = false
    var hotkey = "R"
    var threshold = 25

    init(keyPress: any KeyPressServicing = KeyPressService.shared,
         support: SupportCooldown = .shared) {
        self.keyPress = keyPress
        self.support = support
    }

    func evaluate(hp: NumericReadout, mana: NumericReadout, shield: ShieldReadout,
                  now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let lowHP = hp.state(at: now) == .valid
            && (hp.current ?? 0) > 0 && (hp.maximum ?? 0) > 0
            && Double(hp.current ?? 0) * 100 < Double(hp.maximum ?? 0) * Double(threshold)
        let inactive = shield.state(at: now) == .inactive
        if !lowHP { hpConfirmations = 0 }
        if !inactive { inactiveConfirmations = 0 }
        let hpFrame = hp.captureUptime ?? hp.timestamp?.timeIntervalSinceReferenceDate
        let shieldFrame = shield.captureUptime ?? shield.timestamp?.timeIntervalSinceReferenceDate
        if let hpFrame, previousHP.map({ hpFrame > $0 }) ?? true {
            if previousHP.map({ hpFrame - $0 >= 0.250 }) ?? true { hpConfirmations = 0 }
            previousHP = hpFrame
            hpConfirmations = lowHP ? min(2, hpConfirmations + 1) : 0
        }
        if let shieldFrame, previousShield.map({ shieldFrame > $0 }) ?? true {
            if previousShield.map({ shieldFrame - $0 >= 0.250 }) ?? true { inactiveConfirmations = 0 }
            previousShield = shieldFrame
            inactiveConfirmations = inactive ? min(2, inactiveConfirmations + 1) : 0
        }
        guard enabled, lowHP, inactive, mana.state(at: now) == .valid,
              (mana.current ?? 0) >= 50 else {
            cancelPendingActions(resetConfirmations: false)
            return
        }
        guard hpConfirmations >= 2, inactiveConfirmations >= 2,
              support.isReady(at: uptime),
              hp.timestamp != nil, mana.timestamp != nil, shield.timestamp != nil else { return }
        let validFor = 0.250 - max(hp.freshness(at: now) ?? 0.250, mana.freshness(at: now) ?? 0.250, shield.freshness(at: now) ?? 0.250)
        guard validFor > 0 else { cancelPendingActions(); return }
        let token = UUID()
        let canRequest = lock.withLock { () -> Bool in
            guard pending == nil, uptime - lastAttempt >= 14 else { return false }
            pending = token
            return true
        }
        guard canRequest else { return }
        support.setShieldPending(true)
        keyPress.cancelPendingRequests(in: support.hasteGroup)
        let accepted = keyPress.pressKey(hotkey, priority: .emergency, group: group,
                                        validUntil: uptime + validFor,
                                        isValid: { [support] in support.isReady(at: ProcessInfo.processInfo.systemUptime) }) { [weak self] event in
            guard let self else { return }
            self.lock.withLock {
                if event.phase == .keyDown {
                    self.lastAttempt = event.timestamp
                    self.support.recordKeyDown(at: event.timestamp)
                }
                if event.phase == .keyDown || event.phase == .cancelled || event.phase == .failed {
                    self.support.setShieldPending(false)
                    if self.pending == token { self.pending = nil }
                }
            }
        }
        if !accepted { support.setShieldPending(false); lock.withLock { if pending == token { pending = nil } } }
    }

    func cancelPendingActions(resetConfirmations: Bool = true) {
        keyPress.cancelPendingRequests(in: group)
        support.setShieldPending(false)
        lock.withLock { pending = nil }
        if resetConfirmations {
            hpConfirmations = 0
            inactiveConfirmations = 0
            previousHP = nil
            previousShield = nil
        }
    }
}
