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
    
    private let screenCapture = ScreenCaptureService.shared
    
    /// Debug mode - print OCR results
    var debugMode = true
    private var debugCounter = 0
    
    /// Set regions from config
    func setRegions(hp: (x: Int, y: Int, width: Int, height: Int)?, mana: (x: Int, y: Int, width: Int, height: Int)?) {
        if let hp = hp {
            hpRegion = hp
            print("📍 HP region set: \(hp)")
        }
        if let mana = mana {
            manaRegion = mana
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
                if let result = performOCR(on: cropped, label: shouldDebug ? "HP" : nil) {
                    reading.hpCurrent = result.current
                    reading.hpMax = result.max
                    lastHPCurrent = result.current
                    lastHPMax = result.max
                } else {
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
                if let result = performOCR(on: cropped, label: shouldDebug ? "Mana" : nil) {
                    reading.manaCurrent = result.current
                    reading.manaMax = result.max
                    lastManaCurrent = result.current
                    lastManaMax = result.max
                } else {
                    reading.manaCurrent = lastManaCurrent
                    reading.manaMax = lastManaMax
                }
            } else if shouldDebug {
                print("⚠️ Failed to crop Mana region: \(region)")
            }
        }
        
        return reading
    }
    
    /// Preprocess image for better OCR accuracy
    private func preprocessImage(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        
        // Scale up 3x for better OCR on small text
        let scale = 3
        let newWidth = width * scale
        let newHeight = height * scale
        
        // Create context with grayscale color space for better contrast
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return image
        }
        
        // Draw original image scaled up
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        return context.makeImage() ?? image
    }
    
    /// Perform OCR on image and parse "current/max" format
    private func performOCR(on image: CGImage, label: String? = nil) -> (current: Int, max: Int)? {
        // Preprocess image for better OCR
        let processedImage = preprocessImage(image)
        
        // Create request with accurate recognition for better results
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate  // Use accurate for better digit recognition
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02  // Slightly higher for better accuracy
        
        // Use revision 3 if available
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        
        let handler = VNImageRequestHandler(cgImage: processedImage, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let results = request.results, !results.isEmpty else {
                if let label = label {
                    print("🔍 \(label) OCR: No results (image size: \(image.width)x\(image.height))")
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
            .replacingOccurrences(of: "O", with: "0")  // Common OCR error
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "|", with: "/")  // Pipe often confused with slash
            .replacingOccurrences(of: "\\", with: "/") // Backslash confused with slash
            .replacingOccurrences(of: "S", with: "5")  // S looks like 5
            .replacingOccurrences(of: "s", with: "5")
            .replacingOccurrences(of: "B", with: "8")  // B looks like 8
            .replacingOccurrences(of: "Z", with: "2")  // Z looks like 2
            .replacingOccurrences(of: "z", with: "2")
            .replacingOccurrences(of: "G", with: "6")  // G looks like 6
            .replacingOccurrences(of: "g", with: "9")  // g looks like 9
            .replacingOccurrences(of: "q", with: "9")  // q looks like 9
        
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
        
        // Fix common OCR confusion: 9 often misread as 6 or vice versa
        // If current > max, try swapping 9s and 6s
        if current > max {
            // Try fixing by replacing 9 with 6 in current
            let currentStr = String(current)
            let maxStr = String(max)
            
            // Check if replacing 9 with 6 in either number would help
            if let fixedCurrent = Int(currentStr.replacingOccurrences(of: "9", with: "6")),
               fixedCurrent <= max {
                current = fixedCurrent
            } else if let fixedMax = Int(maxStr.replacingOccurrences(of: "6", with: "9")),
                      current <= fixedMax {
                max = fixedMax
            } else {
                // Still invalid, reject
                return nil
            }
        }
        
        // Validate reasonable values (typical Tibia HP/Mana range)
        if current >= 1 && current <= 99999 && max >= 1 && max <= 99999 {
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
    }
}
