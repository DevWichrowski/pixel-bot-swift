import CoreGraphics
import CoreVideo
import Foundation

enum CaptureRegionKind: String, CaseIterable, Sendable {
    case hp
    case mana
    case ammo
}

/// A region in logical points on the main display, measured from its top-left corner.
struct CaptureRegion: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init?(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        guard x.isFinite,
              y.isFinite,
              width.isFinite,
              height.isFinite,
              x >= 0,
              y >= 0,
              width > 0,
              height > 0 else {
            return nil
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init?(_ region: (x: Int, y: Int, width: Int, height: Int)) {
        self.init(
            x: CGFloat(region.x),
            y: CGFloat(region.y),
            width: CGFloat(region.width),
            height: CGFloat(region.height)
        )
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var integerTuple: (x: Int, y: Int, width: Int, height: Int) {
        (
            x: Int(x.rounded()),
            y: Int(y.rounded()),
            width: Int(width.rounded()),
            height: Int(height.rounded())
        )
    }

    func isContained(in displaySize: CGSize) -> Bool {
        guard displaySize.width.isFinite,
              displaySize.height.isFinite,
              displaySize.width > 0,
              displaySize.height > 0 else {
            return false
        }

        return rect.minX >= 0
            && rect.minY >= 0
            && rect.maxX <= displaySize.width
            && rect.maxY <= displaySize.height
    }
}

struct CaptureRegions: Equatable, Sendable {
    var hp: CaptureRegion?
    var mana: CaptureRegion?
    var ammo: CaptureRegion?

    init(hp: CaptureRegion? = nil, mana: CaptureRegion? = nil, ammo: CaptureRegion? = nil) {
        self.hp = hp
        self.mana = mana
        self.ammo = ammo
    }

    subscript(kind: CaptureRegionKind) -> CaptureRegion? {
        get {
            switch kind {
            case .hp: hp
            case .mana: mana
            case .ammo: ammo
            }
        }
        set {
            switch kind {
            case .hp: hp = newValue
            case .mana: mana = newValue
            case .ammo: ammo = newValue
            }
        }
    }

    var active: [CaptureRegion] {
        [hp, mana, ammo].compactMap { $0 }
    }

    var hasRequiredRegions: Bool {
        hp != nil && mana != nil
    }

    func invalidKinds(for displaySize: CGSize) -> [CaptureRegionKind] {
        CaptureRegionKind.allCases.filter { kind in
            guard let region = self[kind] else { return false }
            return !region.isContained(in: displaySize)
        }
    }

    func sourceRect() -> CGRect? {
        guard let first = active.first else { return nil }

        let union = active.dropFirst().reduce(first.rect) { partial, region in
            partial.union(region.rect)
        }
        return union.integral
    }
}

enum NumericReadoutState: String, Equatable, Sendable {
    case valid
    case stale
    case invalid
    case unconfigured
}

struct NumericReadout: Equatable, Sendable {
    var captureUptime: TimeInterval? = nil
    var current: Int?
    var maximum: Int?
    var confidence: Float
    var timestamp: Date?
    var latency: TimeInterval
    var state: NumericReadoutState
    var lastText: String

    init(
        current: Int? = nil,
        maximum: Int? = nil,
        confidence: Float = 0,
        timestamp: Date? = nil,
        latency: TimeInterval = 0,
        state: NumericReadoutState = .unconfigured,
        lastText: String = ""
    ) {
        self.current = current
        self.maximum = maximum
        self.confidence = confidence
        self.timestamp = timestamp
        self.latency = latency
        self.state = state
        self.lastText = lastText
    }

    func freshness(at date: Date = Date()) -> TimeInterval? {
        captureUptime.map { max(0, ProcessInfo.processInfo.systemUptime - $0) }
            ?? timestamp.map { max(0, date.timeIntervalSince($0)) }
    }

    func state(at date: Date = Date(), staleAfter: TimeInterval = 0.250) -> NumericReadoutState {
        guard state != .unconfigured else { return .unconfigured }
        guard state != .invalid else { return .invalid }
        guard current != nil, let timestamp else { return .invalid }
        let age = captureUptime.map { ProcessInfo.processInfo.systemUptime - $0 } ?? date.timeIntervalSince(timestamp)
        return age >= staleAfter ? .stale : .valid
    }
}

enum ShieldState: String, Equatable, Sendable {
    case active
    case inactive
    case unknown
}

struct ShieldReadout: Equatable, Sendable {
    var captureUptime: TimeInterval? = nil
    var current: Int? = nil
    var maximum: Int? = nil
    var confidence: Float = 0
    var timestamp: Date? = nil
    var state: ShieldState = .unknown

    func freshness(at date: Date = Date()) -> TimeInterval? {
        captureUptime.map { max(0, ProcessInfo.processInfo.systemUptime - $0) }
            ?? timestamp.map { max(0, date.timeIntervalSince($0)) }
    }

    func state(at date: Date = Date(), staleAfter: TimeInterval = 0.250) -> ShieldState {
        guard let age = freshness(at: date), age < staleAfter else { return .unknown }
        return state
    }
}

struct RegionDiagnostic: @unchecked Sendable {
    var rawImage: CGImage?
    var binaryImage: CGImage?
    var text: String
    var confidence: Float
    /// Age of the most recent confirmed valid reading, in seconds.
    var freshness: TimeInterval?
    var latency: TimeInterval
    var state: NumericReadoutState

    init(
        rawImage: CGImage? = nil,
        binaryImage: CGImage? = nil,
        text: String = "",
        confidence: Float = 0,
        freshness: TimeInterval? = nil,
        latency: TimeInterval = 0,
        state: NumericReadoutState = .unconfigured
    ) {
        self.rawImage = rawImage
        self.binaryImage = binaryImage
        self.text = text
        self.confidence = confidence
        self.freshness = freshness
        self.latency = latency
        self.state = state
    }
}

enum BotRunState: String, Equatable, Sendable {
    case stopped
    case needsPermission
    case starting
    case running
    case captureFailed
    case stale
}

struct CaptureRegionTransformer {
    static func pixelRect(
        for region: CaptureRegion,
        sourceRect: CGRect,
        bufferSize: CGSize
    ) -> CGRect? {
        guard sourceRect.width > 0,
              sourceRect.height > 0,
              bufferSize.width > 0,
              bufferSize.height > 0,
              sourceRect.contains(region.rect) else {
            return nil
        }

        let scaleX = bufferSize.width / sourceRect.width
        let scaleY = bufferSize.height / sourceRect.height
        let localMinX = (region.rect.minX - sourceRect.minX) * scaleX
        let localMinY = (region.rect.minY - sourceRect.minY) * scaleY
        let localMaxX = (region.rect.maxX - sourceRect.minX) * scaleX
        let localMaxY = (region.rect.maxY - sourceRect.minY) * scaleY

        let minX = max(0, floor(localMinX))
        let minY = max(0, floor(localMinY))
        let maxX = min(bufferSize.width, ceil(localMaxX))
        let maxY = min(bufferSize.height, ceil(localMaxY))

        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// A retained BGRA frame and the logical source rectangle represented by its pixels.
struct CapturedFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let sourceRect: CGRect
    let generation: UInt64
    let timestamp: Date
    var captureUptime: TimeInterval? = nil

    var pixelSize: CGSize {
        CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
    }

    func pixelRect(for region: CaptureRegion) -> CGRect? {
        CaptureRegionTransformer.pixelRect(
            for: region,
            sourceRect: sourceRect,
            bufferSize: pixelSize
        )
    }
}
