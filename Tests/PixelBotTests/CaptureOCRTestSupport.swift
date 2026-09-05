import CoreVideo
import Foundation
@testable import PixelBot

final class CaptureOCRRecognizerStub: OCRTextRecognizing {
    private let lock = NSLock()
    private var fastResponses: [[OCRTextCandidate]]
    private var accurateResponses: [[OCRTextCandidate]]
    private var storedCalls: [OCRRecognitionMode] = []
    private var storedRequests: [String] = []
    private let beforeResponse: ((OCRRecognitionMode) -> Void)?

    init(
        fast: [[OCRTextCandidate]],
        accurate: [[OCRTextCandidate]] = [],
        beforeResponse: ((OCRRecognitionMode) -> Void)? = nil
    ) {
        fastResponses = fast
        accurateResponses = accurate
        self.beforeResponse = beforeResponse
    }

    func recognize(in image: CGImage, mode: OCRRecognitionMode) throws -> [OCRTextCandidate] {
        beforeResponse?(mode)
        return lock.withLock {
            storedCalls.append(mode)
            let modeName = mode == .fast ? "fast" : "accurate"
            storedRequests.append("\(modeName):\(image.width)x\(image.height)")
            switch mode {
            case .fast:
                return fastResponses.isEmpty ? [] : fastResponses.removeFirst()
            case .accurate:
                return accurateResponses.isEmpty ? [] : accurateResponses.removeFirst()
            }
        }
    }

    var calls: [OCRRecognitionMode] {
        lock.withLock { storedCalls }
    }

    var requests: [String] {
        lock.withLock { storedRequests }
    }
}

final class CaptureOCRLockedBox<Value> {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    func set(_ value: Value) {
        lock.withLock {
            storedValue = value
        }
    }

    var value: Value {
        lock.withLock { storedValue }
    }
}

func captureOCRCandidate(_ text: String, confidence: Float = 0.90) -> [OCRTextCandidate] {
    [OCRTextCandidate(text: text, confidence: confidence)]
}

func makeCaptureOCRFrame(
    pattern: Int,
    generation: UInt64 = 1,
    timestamp: Date = Date(),
    width: Int = 12,
    height: Int = 6,
    sourceRect: CGRect? = nil
) -> CapturedFrame {
    var optionalBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        nil,
        &optionalBuffer
    )
    precondition(status == kCVReturnSuccess && optionalBuffer != nil)
    let pixelBuffer = optionalBuffer!

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
        .assumingMemoryBound(to: UInt8.self)

    for y in 0..<height {
        for x in 0..<width {
            let byteOffset = y * bytesPerRow + x * 4
            let isBright = ((x + y + pattern) % 3) == 0
            let value: UInt8 = isBright ? 255 : 0
            baseAddress[byteOffset] = value
            baseAddress[byteOffset + 1] = value
            baseAddress[byteOffset + 2] = value
            baseAddress[byteOffset + 3] = 255
        }
    }

    return CapturedFrame(
        pixelBuffer: pixelBuffer,
        sourceRect: sourceRect ?? CGRect(x: 0, y: 0, width: width, height: height),
        generation: generation,
        timestamp: timestamp
    )
}

func captureOCRFullRegion(width: Int = 12, height: Int = 6) -> CaptureRegion {
    CaptureRegion(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))!
}

func makeSyntheticDigitFrame(
    scale: Int,
    generation: UInt64 = 1,
    timestamp: Date = Date()
) -> (frame: CapturedFrame, region: CaptureRegion) {
    let glyphs: [Character: [String]] = [
        "1": ["010", "110", "010", "010", "111"],
        "2": ["110", "001", "010", "100", "111"],
        "3": ["110", "001", "010", "001", "110"],
        "4": ["101", "101", "111", "001", "001"],
        "/": ["001", "001", "010", "100", "100"],
    ]
    let text = Array("12/34")
    let logicalWidth = text.count * 4 - 1
    let logicalHeight = 5
    let pixelWidth = logicalWidth * scale
    let pixelHeight = logicalHeight * scale
    var optionalBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        pixelWidth,
        pixelHeight,
        kCVPixelFormatType_32BGRA,
        nil,
        &optionalBuffer
    )
    precondition(status == kCVReturnSuccess && optionalBuffer != nil)
    let pixelBuffer = optionalBuffer!

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
        .assumingMemoryBound(to: UInt8.self)

    for y in 0..<pixelHeight {
        for x in 0..<pixelWidth {
            let logicalX = x / scale
            let logicalY = y / scale
            let glyphIndex = logicalX / 4
            let glyphX = logicalX % 4
            let isDigitPixel: Bool
            if glyphIndex < text.count,
               glyphX < 3,
               let glyph = glyphs[text[glyphIndex]] {
                let row = Array(glyph[logicalY])
                isDigitPixel = row[glyphX] == "1"
            } else {
                isDigitPixel = false
            }

            let offset = y * bytesPerRow + x * 4
            let value: UInt8 = isDigitPixel ? 255 : 0
            baseAddress[offset] = value
            baseAddress[offset + 1] = value
            baseAddress[offset + 2] = value
            baseAddress[offset + 3] = 255
        }
    }

    let sourceRect = CGRect(
        x: 0,
        y: 0,
        width: logicalWidth,
        height: logicalHeight
    )
    return (
        frame: CapturedFrame(
            pixelBuffer: pixelBuffer,
            sourceRect: sourceRect,
            generation: generation,
            timestamp: timestamp
        ),
        region: CaptureRegion(
            x: 0,
            y: 0,
            width: CGFloat(logicalWidth),
            height: CGFloat(logicalHeight)
        )!
    )
}
