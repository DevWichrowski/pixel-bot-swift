import CoreGraphics
import CoreVideo
import Foundation
import Vision

enum RegionCropError: Error, Equatable {
    case unsupportedPixelFormat
    case missingBaseAddress
    case regionOutsideFrame
    case imageCreationFailed
}

enum PixelBufferRegionCropper {
    static func crop(_ region: CaptureRegion, from frame: CapturedFrame) throws -> CGImage {
        guard CVPixelBufferGetPixelFormatType(frame.pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw RegionCropError.unsupportedPixelFormat
        }
        guard let pixelRect = frame.pixelRect(for: region) else {
            throw RegionCropError.regionOutsideFrame
        }

        let x = Int(pixelRect.minX)
        let y = Int(pixelRect.minY)
        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        let sourceWidth = CVPixelBufferGetWidth(frame.pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(frame.pixelBuffer)

        guard x >= 0,
              y >= 0,
              width > 0,
              height > 0,
              x + width <= sourceWidth,
              y + height <= sourceHeight else {
            throw RegionCropError.regionOutsideFrame
        }

        CVPixelBufferLockBaseAddress(frame.pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame.pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(frame.pixelBuffer) else {
            throw RegionCropError.missingBaseAddress
        }

        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(frame.pixelBuffer)
        let destinationBytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: destinationBytesPerRow * height)

        bytes.withUnsafeMutableBytes { destinationBuffer in
            guard let destinationBase = destinationBuffer.baseAddress else { return }

            for row in 0..<height {
                let source = baseAddress
                    .advanced(by: (y + row) * sourceBytesPerRow + x * 4)
                let destination = destinationBase.advanced(by: row * destinationBytesPerRow)
                destination.copyMemory(from: source, byteCount: destinationBytesPerRow)
            }
        }

        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: destinationBytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw RegionCropError.imageCreationFailed
        }

        return image
    }
}

struct PreprocessedRegion {
    let image: CGImage
    let binaryBytes: [UInt8]
    let hash: UInt64
}

enum OCRPreprocessorError: Error {
    case contextCreationFailed
    case imageCreationFailed
}

enum OCRPreprocessingStrategy: UInt8 {
    case adaptiveLuminance
    case whiteText
}

struct OCRImagePreprocessor {
    private static let scale = 3
    private static let whiteTextThreshold = 160
    private let strategy: OCRPreprocessingStrategy

    init(strategy: OCRPreprocessingStrategy = .adaptiveLuminance) {
        self.strategy = strategy
    }

    func process(_ image: CGImage) throws -> PreprocessedRegion {
        let width = image.width * Self.scale
        let height = image.height * Self.scale
        let bytesPerRow = width * 4
        var bgraBytes = [UInt8](repeating: 0, count: bytesPerRow * height)

        let drewImage = bgraBytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                ).rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewImage else { throw OCRPreprocessorError.contextCreationFailed }

        let binaryBytes: [UInt8]
        switch strategy {
        case .adaptiveLuminance:
            var luminance = [UInt8](repeating: 0, count: width * height)
            var histogram = [Int](repeating: 0, count: 256)

            for pixel in 0..<(width * height) {
                let byteIndex = pixel * 4
                let blue = Int(bgraBytes[byteIndex])
                let green = Int(bgraBytes[byteIndex + 1])
                let red = Int(bgraBytes[byteIndex + 2])
                let value = UInt8(clamping: (299 * red + 587 * green + 114 * blue) / 1000)
                luminance[pixel] = value
                histogram[Int(value)] += 1
            }

            let threshold = otsuThreshold(histogram: histogram, pixelCount: luminance.count)
            var adaptiveBytes = [UInt8](repeating: 255, count: luminance.count)
            for index in luminance.indices {
                adaptiveBytes[index] = luminance[index] > threshold ? 0 : 255
            }
            binaryBytes = adaptiveBytes

        case .whiteText:
            var whiteTextBytes = [UInt8](repeating: 255, count: width * height)
            for pixel in whiteTextBytes.indices {
                let byteIndex = pixel * 4
                let blue = Int(bgraBytes[byteIndex])
                let green = Int(bgraBytes[byteIndex + 1])
                let red = Int(bgraBytes[byteIndex + 2])
                let isWhiteText = red > Self.whiteTextThreshold
                    && green > Self.whiteTextThreshold
                    && blue > Self.whiteTextThreshold
                    && max(red, green, blue) - min(red, green, blue) <= 40
                whiteTextBytes[pixel] = isWhiteText ? 0 : 255
            }
            binaryBytes = whiteTextBytes
        }

        let data = Data(binaryBytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let binaryImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw OCRPreprocessorError.imageCreationFailed
        }

        return PreprocessedRegion(
            image: binaryImage,
            binaryBytes: binaryBytes,
            hash: stableHash(bytes: bgraBytes + [strategy.rawValue], width: width, height: height)
        )
    }

    private func otsuThreshold(histogram: [Int], pixelCount: Int) -> UInt8 {
        guard pixelCount > 0 else { return 0 }

        var totalWeightedValue = 0
        for value in histogram.indices {
            totalWeightedValue += value * histogram[value]
        }

        var backgroundWeight = 0
        var backgroundWeightedValue = 0
        var bestVariance = -Double.infinity
        var bestThreshold = 0

        for threshold in histogram.indices {
            backgroundWeight += histogram[threshold]
            guard backgroundWeight > 0 else { continue }

            let foregroundWeight = pixelCount - backgroundWeight
            guard foregroundWeight > 0 else { break }

            backgroundWeightedValue += threshold * histogram[threshold]
            let backgroundMean = Double(backgroundWeightedValue) / Double(backgroundWeight)
            let foregroundMean = Double(totalWeightedValue - backgroundWeightedValue) / Double(foregroundWeight)
            let meanDifference = backgroundMean - foregroundMean
            let betweenClassVariance = Double(backgroundWeight)
                * Double(foregroundWeight)
                * meanDifference
                * meanDifference

            if betweenClassVariance > bestVariance {
                bestVariance = betweenClassVariance
                bestThreshold = threshold
            }
        }

        return UInt8(bestThreshold)
    }

    private func stableHash(bytes: [UInt8], width: Int, height: Int) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for dimension in [UInt64(width), UInt64(height)] {
            var value = dimension
            for _ in 0..<MemoryLayout<UInt64>.size {
                hash ^= value & 0xff
                hash = hash &* prime
                value >>= 8
            }
        }

        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

enum NumericOCRFormat: Sendable {
    case currentAndMaximum
    case manaAndShield
    case singleValue
}

struct ParsedNumericValue: Equatable, Sendable {
    let current: Int
    let maximum: Int?
}

struct NumericOCRParser {
    private static let currentMaximumRegex = makeRegex(#"^([0-9]{1,5})/([0-9]{1,5})$"#)
    private static let singleValueRegex = makeRegex(#"^([0-9]{1,5})$"#)

    func parse(_ text: String, format: NumericOCRFormat) -> ParsedNumericValue? {
        let normalized = normalize(text)

        switch format {
        case .manaAndShield:
            return ManaOCRParser().parse(text).mana
        case .currentAndMaximum:
            if let match = Self.currentMaximumRegex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
            ),
               let currentRange = Range(match.range(at: 1), in: normalized),
               let maximumRange = Range(match.range(at: 2), in: normalized),
               let current = Int(normalized[currentRange]),
               let maximum = Int(normalized[maximumRange]),
               current >= 0,
               current <= maximum,
               maximum <= 99_999 {
                return ParsedNumericValue(current: current, maximum: maximum)
            }
            return parseCurrentAndMaximumWithMisreadSeparator(normalized)

        case .singleValue:
            guard let match = Self.singleValueRegex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
            ),
            let valueRange = Range(match.range(at: 1), in: normalized),
            let value = Int(normalized[valueRange]),
            value >= 0,
            value <= 99_999 else {
                return nil
            }
            return ParsedNumericValue(current: value, maximum: nil)
        }
    }

    private func parseCurrentAndMaximumWithMisreadSeparator(
        _ normalized: String
    ) -> ParsedNumericValue? {
        guard (3...11).contains(normalized.count),
              normalized.allSatisfy({ ("0"..."9").contains($0) }) else {
            return nil
        }

        let candidates: [(value: ParsedNumericValue, digitDifference: Int)] =
            normalized.indices.compactMap { separatorIndex in
                guard normalized[separatorIndex] == "1" else { return nil }

                let currentText = normalized[..<separatorIndex]
                let maximumStart = normalized.index(after: separatorIndex)
                let maximumText = normalized[maximumStart...]
                guard (1...5).contains(currentText.count),
                      (1...5).contains(maximumText.count),
                      let current = Int(currentText),
                      let maximum = Int(maximumText),
                      current <= maximum,
                      maximum <= 99_999 else {
                    return nil
                }

                return (
                    ParsedNumericValue(current: current, maximum: maximum),
                    abs(currentText.count - maximumText.count)
                )
            }

        guard let smallestDifference = candidates.map(\.digitDifference).min() else {
            return nil
        }
        let bestCandidates = candidates.filter { $0.digitDifference == smallestDifference }
        guard bestCandidates.count == 1 else { return nil }
        return bestCandidates[0].value
    }

    func normalize(_ text: String) -> String {
        String(text.compactMap { character -> Character? in
            if character.isWhitespace {
                return nil
            }

            switch character {
            case "O", "o": return "0"
            case "I", "l": return "1"
            case "|", "\\": return "/"
            default: return character
            }
        })
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("Invalid static OCR regular expression")
        }
        return regex
    }
}

struct ParsedManaReadout: Equatable, Sendable {
    let mana: ParsedNumericValue?
    let shield: ParsedNumericValue?
}

/// Parentheses delimit a separate field. Never salvage a shield-only pair as mana.
struct ManaOCRParser {
    func parse(_ text: String) -> ParsedManaReadout {
        let parser = NumericOCRParser()
        let normalized = parser.normalize(text)
            .replacingOccurrences(of: "{", with: "(")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "}", with: ")")
            .replacingOccurrences(of: "]", with: ")")
        let parts = normalized.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false)
        let mana = parsePair(String(parts[0]))
        guard parts.count == 2, parts[1].hasSuffix(")") else {
            return ParsedManaReadout(mana: mana, shield: nil)
        }
        let shield = parsePair(String(parts[1].dropLast()))
        return ParsedManaReadout(mana: mana, shield: shield)
    }

    private func parsePair(_ text: String) -> ParsedNumericValue? {
        let parser = NumericOCRParser()
        if text.contains("/") {
            return parser.parse(text, format: .currentAndMaximum)
        }
        guard (3...11).contains(text.count), text.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        let candidates = text.indices.compactMap { index -> ParsedNumericValue? in
            guard text[index] == "1" else { return nil }
            return parser.parse(String(text[..<index]) + "/" + String(text[text.index(after: index)...]), format: .currentAndMaximum)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

}

enum OCRRecognitionMode: Equatable, Sendable {
    case fast
    case accurate
}

enum OCRPipelineMode: Equatable, Sendable {
    case realtime
    case diagnostic
}

struct OCRTextCandidate: Equatable, Sendable {
    let text: String
    let confidence: Float
    var bounds: CGRect? = nil
    var isLeading: Bool = true
}

protocol OCRTextRecognizing: AnyObject {
    func recognize(in image: CGImage, mode: OCRRecognitionMode) throws -> [OCRTextCandidate]
}

final class VisionTextRecognizer: OCRTextRecognizing {
    private let fastRequest: VNRecognizeTextRequest
    private let accurateRequest: VNRecognizeTextRequest

    init() {
        fastRequest = Self.makeRequest(level: .fast)
        accurateRequest = Self.makeRequest(level: .accurate)
    }

    func recognize(in image: CGImage, mode: OCRRecognitionMode) throws -> [OCRTextCandidate] {
        let request = mode == .fast ? fastRequest : accurateRequest
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        guard let first = observations.first else { return [] }
        // Retain left-to-right geometry. A right-hand observation cannot independently
        // become the leading numeric field when the mana observation was rejected.
        let row = observations.filter { abs($0.boundingBox.midY - first.boundingBox.midY) < 0.25 }
        var candidates: [OCRTextCandidate] = []
        for rank in 0..<3 {
            let texts = row.compactMap { observation -> VNRecognizedText? in
                let alternatives = observation.topCandidates(3)
                return alternatives.indices.contains(rank) ? alternatives[rank] : alternatives.first
            }
            if !texts.isEmpty {
                candidates.append(OCRTextCandidate(
                    text: texts.map(\.string).joined(separator: " "),
                    confidence: texts.map(\.confidence).min() ?? 0,
                    bounds: row.reduce(first.boundingBox) { $0.union($1.boundingBox) }
                ))
            }
        }
        return candidates
    }

    private static func makeRequest(level: VNRequestTextRecognitionLevel) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02
        request.revision = VNRecognizeTextRequestRevision3
        return request
    }
}

struct RegionOCRProcessResult {
    let readout: NumericReadout
    let diagnostic: RegionDiagnostic
    let confirmedCurrent: Int?
    let recognitionModes: [OCRRecognitionMode]
    let wasCacheHit: Bool
}

struct NumericRegionOCRPipeline {
    static let staleInterval: TimeInterval = 0.250
    static let accurateFallbackThreshold: Float = 0.60

    private struct AcceptedCandidate {
        let value: ParsedNumericValue
        let text: String
        let confidence: Float
        var shieldValue: ParsedNumericValue? = nil
    }

    private let format: NumericOCRFormat
    private let mode: OCRPipelineMode
    private let requiredConfirmations: Int
    private let recognizer: OCRTextRecognizing
    private let parser = NumericOCRParser()
    private let preprocessor: OCRImagePreprocessor

    private(set) var shield = ShieldReadout()
    private(set) var readout: NumericReadout
    private(set) var diagnostic: RegionDiagnostic
    private var frameCaptureUptime: TimeInterval?
    private var acceptedHash: UInt64?
    private var acceptedCandidate: AcceptedCandidate?
    private var pendingMaximum: Int?
    private var pendingMaximumCount = 0
    private var pendingValue: ParsedNumericValue?
    private var pendingValueCount = 0
    private var pendingValueTimestamp: Date?
    private var confirmedValue: ParsedNumericValue?

    init(
        format: NumericOCRFormat,
        configured: Bool = false,
        mode: OCRPipelineMode = .realtime,
        requiredConfirmations: Int = 1,
        recognizer: OCRTextRecognizing = VisionTextRecognizer()
    ) {
        self.format = format
        self.mode = mode
        self.requiredConfirmations = max(1, requiredConfirmations)
        self.recognizer = recognizer
        switch format {
        case .currentAndMaximum, .manaAndShield:
            preprocessor = OCRImagePreprocessor(strategy: .whiteText)
        case .singleValue:
            preprocessor = OCRImagePreprocessor(strategy: .adaptiveLuminance)
        }
        let initialState: NumericReadoutState = configured ? .invalid : .unconfigured
        readout = NumericReadout(state: initialState)
        diagnostic = RegionDiagnostic(state: initialState)
    }

    mutating func reset(configured: Bool) {
        shield = ShieldReadout()
        let state: NumericReadoutState = configured ? .invalid : .unconfigured
        readout = NumericReadout(state: state)
        diagnostic = RegionDiagnostic(state: state)
        acceptedHash = nil
        acceptedCandidate = nil
        pendingMaximum = nil
        pendingMaximumCount = 0
        pendingValue = nil
        pendingValueCount = 0
        pendingValueTimestamp = nil
        confirmedValue = nil
    }

    mutating func process(
        frame: CapturedFrame,
        region: CaptureRegion,
        now: Date? = nil
    ) -> RegionOCRProcessResult {
        frameCaptureUptime = frame.captureUptime
        let startTime = ProcessInfo.processInfo.systemUptime
        shield = ShieldReadout()

        do {
            let rawImage = try PixelBufferRegionCropper.crop(region, from: frame)
            let preprocessed = try preprocessor.process(rawImage)
            let preprocessingCompletedAt = now ?? Date()
            invalidateConfirmedValueIfReadoutIsStale(at: preprocessingCompletedAt)

            if preprocessed.hash == acceptedHash,
               let acceptedCandidate,
               requiredConfirmations == 1 || confirmedValue == acceptedCandidate.value {
                DiagnosticMetrics.shared.record(.cacheHits)
                let latency = ProcessInfo.processInfo.systemUptime - startTime
                let evaluatedAt = now ?? Date()
                guard isFresh(frame: frame, at: evaluatedAt) else {
                    resetPendingConfirmation(invalidateConfirmedValue: true)
                    diagnostic = RegionDiagnostic(
                        rawImage: rawImage,
                        binaryImage: preprocessed.image,
                        text: acceptedCandidate.text,
                        confidence: acceptedCandidate.confidence,
                        freshness: max(0, evaluatedAt.timeIntervalSince(frame.timestamp)),
                        latency: latency,
                        state: readout.state(at: evaluatedAt, staleAfter: Self.staleInterval)
                    )
                    return result(
                        at: evaluatedAt,
                        confirmedCurrent: nil,
                        recognitionModes: [],
                        wasCacheHit: true
                    )
                }
                invalidateConfirmedValueIfReadoutIsStale(at: evaluatedAt)
                let confirmed = confirm(acceptedCandidate.value, timestamp: frame.timestamp)
                let accepted = confirmed && apply(
                    acceptedCandidate,
                    timestamp: frame.timestamp,
                    latency: latency
                )
                diagnostic = RegionDiagnostic(
                    rawImage: rawImage,
                    binaryImage: preprocessed.image,
                    text: acceptedCandidate.text,
                    confidence: acceptedCandidate.confidence,
                    freshness: max(0, evaluatedAt.timeIntervalSince(frame.timestamp)),
                    latency: latency,
                    state: accepted ? .valid : .invalid
                )
                return result(
                    at: evaluatedAt,
                    confirmedCurrent: accepted ? acceptedCandidate.value.current : nil,
                    recognitionModes: [],
                    wasCacheHit: true
                )
            }

            let recognition = try recognize(
                preprocessedImage: preprocessed.image,
                rawImage: rawImage
            )
            let latency = ProcessInfo.processInfo.systemUptime - startTime
            let evaluatedAt = now ?? Date()

            guard let selected = recognition.selected else {
                DiagnosticMetrics.shared.record(.recognitionFailures)
                pendingMaximum = nil
                pendingMaximumCount = 0
                resetPendingConfirmation(invalidateConfirmedValue: true)
                markInvalidIfNeeded()
                diagnostic = RegionDiagnostic(
                    rawImage: rawImage,
                    binaryImage: preprocessed.image,
                    text: recognition.diagnosticCandidate?.text ?? "",
                    confidence: recognition.diagnosticCandidate?.confidence ?? 0,
                    freshness: readout.freshness(at: evaluatedAt),
                    latency: latency,
                    state: .invalid
                )
                return result(
                    at: evaluatedAt,
                    confirmedCurrent: nil,
                    recognitionModes: recognition.modes,
                    wasCacheHit: false
                )
            }

            guard isFresh(frame: frame, at: evaluatedAt) else {
                resetPendingConfirmation(invalidateConfirmedValue: true)
                diagnostic = RegionDiagnostic(
                    rawImage: rawImage,
                    binaryImage: preprocessed.image,
                    text: selected.text,
                    confidence: selected.confidence,
                    freshness: max(0, evaluatedAt.timeIntervalSince(frame.timestamp)),
                    latency: latency,
                    state: readout.state(at: evaluatedAt, staleAfter: Self.staleInterval)
                )
                return result(
                    at: evaluatedAt,
                    confirmedCurrent: nil,
                    recognitionModes: recognition.modes,
                    wasCacheHit: false
                )
            }

            acceptedHash = preprocessed.hash
            acceptedCandidate = selected
            invalidateConfirmedValueIfReadoutIsStale(at: evaluatedAt)
            let confirmed = confirm(selected.value, timestamp: frame.timestamp)
            let accepted = confirmed && apply(
                selected,
                timestamp: frame.timestamp,
                latency: latency
            )
            diagnostic = RegionDiagnostic(
                rawImage: rawImage,
                binaryImage: preprocessed.image,
                text: selected.text,
                confidence: selected.confidence,
                freshness: max(0, evaluatedAt.timeIntervalSince(frame.timestamp)),
                latency: latency,
                state: accepted ? .valid : .invalid
            )
            return result(
                at: evaluatedAt,
                confirmedCurrent: accepted ? selected.value.current : nil,
                recognitionModes: recognition.modes,
                wasCacheHit: false
            )
        } catch {
            pendingMaximum = nil
            pendingMaximumCount = 0
            resetPendingConfirmation(invalidateConfirmedValue: true)
            markInvalidIfNeeded()
            let evaluatedAt = now ?? Date()
            diagnostic = RegionDiagnostic(
                text: "",
                confidence: 0,
                freshness: readout.freshness(at: evaluatedAt),
                latency: ProcessInfo.processInfo.systemUptime - startTime,
                state: .invalid
            )
            return result(
                at: evaluatedAt,
                confirmedCurrent: nil,
                recognitionModes: [],
                wasCacheHit: false
            )
        }
    }

    func readout(at date: Date = Date()) -> NumericReadout {
        var snapshot = readout
        snapshot.state = snapshot.state(at: date, staleAfter: Self.staleInterval)
        return snapshot
    }

    func diagnostic(at date: Date = Date()) -> RegionDiagnostic {
        var snapshot = diagnostic
        snapshot.freshness = readout.freshness(at: date)
        if snapshot.state == .valid {
            snapshot.state = readout.state(at: date, staleAfter: Self.staleInterval)
        }
        return snapshot
    }

    private func recognize(
        preprocessedImage: CGImage,
        rawImage: CGImage
    ) throws -> (
        selected: AcceptedCandidate?,
        diagnosticCandidate: OCRTextCandidate?,
        modes: [OCRRecognitionMode]
    ) {
        let fastCandidates = try recognizer.recognize(
            in: preprocessedImage,
            mode: .fast
        ).prefix(3)
        let fastSelection = bestValidCandidate(in: fastCandidates)
        var allCandidates = Array(fastCandidates)
        var modes: [OCRRecognitionMode] = [.fast]

        let shouldUseAccurateFallback: Bool
        let accurateImage: CGImage
        switch format {
        case .currentAndMaximum:
            shouldUseAccurateFallback = fastSelection == nil
                || (mode == .diagnostic
                    && (fastSelection?.confidence ?? 0) < Self.accurateFallbackThreshold)
            accurateImage = rawImage
        case .manaAndShield:
            shouldUseAccurateFallback = fastSelection == nil
                || fastSelection?.shieldValue == nil
            accurateImage = preprocessedImage
        case .singleValue:
            shouldUseAccurateFallback = mode == .diagnostic
                && (fastSelection == nil
                    || (fastSelection?.confidence ?? 0) < Self.accurateFallbackThreshold)
            accurateImage = preprocessedImage
        }
        if shouldUseAccurateFallback {
            DiagnosticMetrics.shared.record(.recognitionFallbacks)
            let accurateCandidates = (try? recognizer.recognize(
                in: accurateImage,
                mode: .accurate
            ))?.prefix(3) ?? []
            modes.append(.accurate)
            allCandidates.append(contentsOf: accurateCandidates)
        }

        let selected = bestValidCandidate(in: allCandidates)
        let diagnosticCandidate = allCandidates.max { left, right in
            left.confidence < right.confidence
        }
        return (selected, diagnosticCandidate, modes)
    }

    private func bestValidCandidate<C: Collection>(in candidates: C) -> AcceptedCandidate?
    where C.Element == OCRTextCandidate {
        let validCandidates = candidates.compactMap { candidate -> AcceptedCandidate? in
            guard candidate.isLeading,
                  format != .manaAndShield || (candidate.bounds?.minX ?? 0) < 0.5,
                  let value = parser.parse(candidate.text, format: format) else { return nil }
            return AcceptedCandidate(
                value: value,
                text: candidate.text,
                confidence: candidate.confidence,
                shieldValue: format == .manaAndShield ? ManaOCRParser().parse(candidate.text).shield : nil
            )
        }
        guard var best = validCandidates.max(by: { $0.confidence < $1.confidence }) else { return nil }
        guard format == .manaAndShield else { return best }
        let complete = validCandidates.filter { $0.shieldValue != nil }
        guard validCandidates.allSatisfy({ $0.value == best.value }),
              let capacity = complete.first?.shieldValue,
              complete.allSatisfy({ $0.shieldValue == capacity }) else {
            best.shieldValue = nil
            return best
        }
        return complete.max(by: { $0.confidence < $1.confidence })
    }

    @discardableResult
    private mutating func apply(
        _ candidate: AcceptedCandidate,
        timestamp: Date,
        latency: TimeInterval
    ) -> Bool {
        guard let observedMaximum = candidate.value.maximum else {
            accept(candidate, timestamp: timestamp, latency: latency)
            readout.maximum = nil
            return true
        }

        guard let currentMaximum = readout.maximum else {
            accept(candidate, timestamp: timestamp, latency: latency)
            readout.maximum = observedMaximum
            pendingMaximum = nil
            pendingMaximumCount = 0
            return true
        }

        guard observedMaximum != currentMaximum else {
            accept(candidate, timestamp: timestamp, latency: latency)
            pendingMaximum = nil
            pendingMaximumCount = 0
            return true
        }

        if requiredConfirmations > 1 {
            accept(candidate, timestamp: timestamp, latency: latency)
            readout.maximum = observedMaximum
            pendingMaximum = nil
            pendingMaximumCount = 0
            return true
        }

        if pendingMaximum == observedMaximum {
            pendingMaximumCount += 1
        } else {
            pendingMaximum = observedMaximum
            pendingMaximumCount = 1
        }

        if pendingMaximumCount >= 2 {
            accept(candidate, timestamp: timestamp, latency: latency)
            readout.maximum = observedMaximum
            pendingMaximum = nil
            pendingMaximumCount = 0
            return true
        }
        return false
    }

    private mutating func confirm(_ value: ParsedNumericValue, timestamp: Date) -> Bool {
        guard requiredConfirmations > 1 else { return true }
        guard confirmedValue != value else { return true }

        let confirmationAge = pendingValueTimestamp.map { timestamp.timeIntervalSince($0) }
        if pendingValue == value,
           let confirmationAge,
           confirmationAge > 0,
           confirmationAge < Self.staleInterval {
            pendingValueCount += 1
        } else {
            pendingValue = value
            pendingValueCount = 1
        }
        pendingValueTimestamp = timestamp
        guard pendingValueCount >= requiredConfirmations else { return false }

        confirmedValue = value
        resetPendingConfirmation()
        return true
    }

    private func isFresh(frame: CapturedFrame, at date: Date) -> Bool {
        (frame.captureUptime.map { ProcessInfo.processInfo.systemUptime - $0 }
            ?? date.timeIntervalSince(frame.timestamp)) < Self.staleInterval
    }

    private mutating func invalidateConfirmedValueIfReadoutIsStale(at date: Date) {
        guard requiredConfirmations > 1,
              confirmedValue != nil,
              readout.state(at: date, staleAfter: Self.staleInterval) == .stale else {
            return
        }
        resetPendingConfirmation(invalidateConfirmedValue: true)
    }

    private mutating func resetPendingConfirmation(invalidateConfirmedValue: Bool = false) {
        pendingValue = nil
        pendingValueCount = 0
        pendingValueTimestamp = nil
        if invalidateConfirmedValue {
            confirmedValue = nil
        }
    }

    private mutating func accept(
        _ candidate: AcceptedCandidate,
        timestamp: Date,
        latency: TimeInterval
    ) {
        if format == .manaAndShield, let capacity = candidate.shieldValue {
            shield = ShieldReadout(captureUptime: frameCaptureUptime, current: capacity.current, maximum: capacity.maximum,
                                   confidence: candidate.confidence, timestamp: timestamp,
                                   state: capacity.current > 0 ? .active : .inactive)
        }
        readout.captureUptime = frameCaptureUptime
        readout.current = candidate.value.current
        readout.confidence = candidate.confidence
        readout.timestamp = timestamp
        readout.latency = latency
        readout.state = .valid
        readout.lastText = candidate.text
    }

    private mutating func markInvalidIfNeeded() {
        readout.state = .invalid
    }

    private func result(
        at date: Date,
        confirmedCurrent: Int?,
        recognitionModes: [OCRRecognitionMode],
        wasCacheHit: Bool
    ) -> RegionOCRProcessResult {
        let currentReadout = readout(at: date)
        return RegionOCRProcessResult(
            readout: currentReadout,
            diagnostic: diagnostic(at: date),
            confirmedCurrent: currentReadout.state == .valid ? confirmedCurrent : nil,
            recognitionModes: recognitionModes,
            wasCacheHit: wasCacheHit
        )
    }
}
