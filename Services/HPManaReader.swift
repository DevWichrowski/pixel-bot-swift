import Foundation
import Vision
import CoreGraphics
import AppKit

/// Reads HP and Mana values from screen regions using Vision OCR
class HPManaReader {
    /// User-defined regions (x, y, width, height)
    var hpRegion: (x: Int, y: Int, width: Int, height: Int)?
    var manaRegion: (x: Int, y: Int, width: Int, height: Int)?
    
    /// Cache last valid readings
    private var lastHPCurrent: Int?
    private var lastHPMax: Int?
    private var lastManaCurrent: Int?
    private var lastManaMax: Int?
    
    // Cache for image hashes to skip redundant OCR
    private var lastHPHash: Int = 0
    private var lastManaHash: Int = 0
    
    private let screenCapture = ScreenCaptureService.shared
    
    /// Debug mode - print OCR results
    var debugMode = true
    private var debugCounter = 0
    
    // Reuse request
    private lazy var recognitionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate 
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        return request
    }()
    
    /// Set regions from config
    func setRegions(hp: (x: Int, y: Int, width: Int, height: Int)?, mana: (x: Int, y: Int, width: Int, height: Int)?) {
        if let hp = hp {
            hpRegion = hp
            lastHPHash = 0
            print("📍 HP region set: \(hp)")
        }
        if let mana = mana {
            manaRegion = mana
            lastManaHash = 0
            print("📍 Mana region set: \(mana)")
        }
    }
    
    /// Check if both regions are configured
    var isConfigured: Bool {
        hpRegion != nil && manaRegion != nil
    }
    
    /// Read both HP and Mana from a screenshot
    func readStatus(from screenshot: CGImage) -> StatusReading {
        var reading = StatusReading()
        
        debugCounter += 1
        let shouldDebug = debugMode && debugCounter % 20 == 1 // Debug every 20 reads (2 seconds)
        
        // Read HP
        if let region = hpRegion {
            if let cropped = screenCapture.cropRegion(from: screenshot, region: region) {
                
                let currentHash = computeFastHash(cropped)
                if currentHash != lastHPHash {
                    // Changed -> perform OCR
                    if let result = performOCR(on: cropped, label: shouldDebug ? "HP" : nil) {
                        reading.hpCurrent = result.current
                        reading.hpMax = result.max
                        lastHPCurrent = result.current
                        lastHPMax = result.max
                    } else {
                        reading.hpCurrent = lastHPCurrent
                        reading.hpMax = lastHPMax
                    }
                    lastHPHash = currentHash
                } else {
                    // Unchanged -> use cached
                    reading.hpCurrent = lastHPCurrent
                    reading.hpMax = lastHPMax
                }
            } else if shouldDebug {
                print("⚠️ Failed to crop HP region: \(region)")
            }
        }
        
        // Read Mana
        if let region = manaRegion {
            if let cropped = screenCapture.cropRegion(from: screenshot, region: region) {
                
                let currentHash = computeFastHash(cropped)
                if currentHash != lastManaHash {
                    // Changed -> perform OCR
                    if let result = performOCR(on: cropped, label: shouldDebug ? "Mana" : nil) {
                        reading.manaCurrent = result.current
                        reading.manaMax = result.max
                        lastManaCurrent = result.current
                        lastManaMax = result.max
                    } else {
                        reading.manaCurrent = lastManaCurrent
                        reading.manaMax = lastManaMax
                    }
                    lastManaHash = currentHash
                } else {
                    // Unchanged -> use cached
                    reading.manaCurrent = lastManaCurrent
                    reading.manaMax = lastManaMax
                }
            } else if shouldDebug {
                print("⚠️ Failed to crop Mana region: \(region)")
            }
        }
        
        return reading
    }
    
    private func computeFastHash(_ image: CGImage) -> Int {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data else {
            return 0
        }
        let pointer = CFDataGetBytePtr(data)!
        let length = CFDataGetLength(data)
        
        var hash = 5381
        let step = 4 
        
        for i in stride(from: 0, to: length, by: step) {
            hash = ((hash << 5) &+ hash) &+ Int(pointer[i])
        }
        return hash
    }
    
    /// Preprocess image for better OCR accuracy
    private func preprocessImage(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        
        // Scale up 3x for better OCR on small text (kept 3x as it was working, or should I incresase? 3x is usually fine for HP bar text)
        // User asked to "do the same", AmmoReader uses 6x.
        // HP text might be smaller/larger. Let's stick to 3x first, if it fails increase.
        // Or better, safe bet: 4x.
        let scale = 4
        let newWidth = width * scale
        let newHeight = height * scale
        
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        guard let scaledImage = context.makeImage(),
              let dataProvider = scaledImage.dataProvider,
              let data = dataProvider.data else {
            return image
        }
        
        let pointer = CFDataGetBytePtr(data)!
        let length = CFDataGetLength(data)
        var outputData = [UInt8](repeating: 0, count: length) // Initialize Black (bg)
        
        // COLOR FILTERING
        // Target: White (255, 255, 255)
        // Tolerance: +/- 10-20?
        // User provided: #ffffff.
        
        for i in stride(from: 0, to: length, by: 4) {
            let r = Int(pointer[i])
            let g = Int(pointer[i + 1])
            let b = Int(pointer[i + 2])
            
            // Strict white filter
            // Allow some tolerance for anti-aliasing
            let isWhite = r > 220 && g > 220 && b > 220
            
            if isWhite {
                // Make Text Black (Vision prefers black on white? Or white on black?)
                // Usually black text on white bg is standard for docs.
                // In AmmoReader we did: Text=Black(0), Bg=White(255).
                // Let's do the same here.
                
                outputData[i] = 0
                outputData[i+1] = 0
                outputData[i+2] = 0
                outputData[i+3] = 255
            } else {
                // Make Background White
                outputData[i] = 255
                outputData[i+1] = 255
                outputData[i+2] = 255
                outputData[i+3] = 255
            }
        }
        
        let outputPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        outputPtr.initialize(from: &outputData, count: length)
        
        guard let outputContext = CGContext(
            data: outputPtr,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            outputPtr.deallocate()
            return image
        }
        
        let result = outputContext.makeImage() ?? image
        outputPtr.deallocate()
        return result
    }
    
    /// Perform OCR on image and parse "current/max" format
    private func performOCR(on image: CGImage, label: String? = nil) -> (current: Int, max: Int)? {
        let processedImage = preprocessImage(image)
        let handler = VNImageRequestHandler(cgImage: processedImage, options: [:])
        
        do {
            try handler.perform([recognitionRequest])
            
            guard let results = recognitionRequest.results, !results.isEmpty else {
                if let label = label {
                    print("🔍 \(label) OCR: No results")
                }
                return nil
            }
            
            // Collect all text from observations
            var allTexts: [String] = []
            for observation in results {
                if let text = observation.topCandidates(1).first?.string {
                    allTexts.append(text)
                }
            }
            
            if let label = label {
                print("🔍 \(label) OCR raw: \(allTexts)")
            }
            
            // Try to find "current/max" pattern in any result
            for text in allTexts {
                if let parsed = parseCurrentMax(text) {
                    if let label = label {
                        print("✅ \(label) parsed: \(parsed.current)/\(parsed.max)")
                    }
                    return parsed
                }
            }
            
            // Try combining texts if they're separate
            let combined = allTexts.joined()
            if let parsed = parseCurrentMax(combined) {
                if let label = label {
                    print("✅ \(label) parsed (combined): \(parsed.current)/\(parsed.max)")
                }
                return parsed
            }
            
        } catch {
            if let label = label {
                print("⚠️ \(label) OCR error: \(error)")
            }
        }
        
        return nil
    }
    
    /// Parse "current/max" format (e.g., "1301/1301")
    private func parseCurrentMax(_ text: String) -> (current: Int, max: Int)? {
        // Clean text - remove spaces, common OCR errors
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "S", with: "5")
            .replacingOccurrences(of: "s", with: "5")
            .replacingOccurrences(of: "B", with: "8")
            .replacingOccurrences(of: "Z", with: "2")
            .replacingOccurrences(of: "z", with: "2")
            // G -> 6, q/g -> 9 removed as they might overcorrect.
        
        // Match pattern: digits/digits
        let pattern = #"(\d+)/(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) else {
            return nil
        }
        
        guard let currentRange = Range(match.range(at: 1), in: cleaned),
              let maxRange = Range(match.range(at: 2), in: cleaned),
              var current = Int(cleaned[currentRange]),
              var max = Int(cleaned[maxRange]) else {
            return nil
        }
        
        // Auto-correct 9 vs 6 confusion if current > max
        if current > max {
            let currentStr = String(current)
            let maxStr = String(max)
            
            if let fixedCurrent = Int(currentStr.replacingOccurrences(of: "9", with: "6")),
               fixedCurrent <= max {
                current = fixedCurrent
            } else if let fixedMax = Int(maxStr.replacingOccurrences(of: "6", with: "9")),
                      current <= fixedMax {
                max = fixedMax
            }
        }
        
        // Validate reasonable values
        if current >= 0 && current <= 99999 && max >= 1 && max <= 99999 {
            return (current, max)
        }
        
        return nil
    }
    
    /// Reset cached values
    func reset() {
        lastHPCurrent = nil
        lastHPMax = nil
        lastManaCurrent = nil
        lastManaMax = nil
        lastHPHash = 0
        lastManaHash = 0
    }
}
