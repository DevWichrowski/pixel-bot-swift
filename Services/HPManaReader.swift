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
    
    /// Perform OCR on image and parse "current/max" format
    private func performOCR(on image: CGImage, label: String? = nil) -> (current: Int, max: Int)? {
        // Create request with accurate recognition for better results
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate  // Use accurate for better digit recognition
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.0  // Recognize even small text
        
        // Use revision 3 if available
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
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
        var cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "O", with: "0")  // Common OCR error
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "|", with: "/")  // Pipe often confused with slash
        
        // Match pattern: digits/digits
        let pattern = #"(\d+)/(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) else {
            return nil
        }
        
        guard let currentRange = Range(match.range(at: 1), in: cleaned),
              let maxRange = Range(match.range(at: 2), in: cleaned),
              let current = Int(cleaned[currentRange]),
              let max = Int(cleaned[maxRange]) else {
            return nil
        }
        
        // Validate: current can never be greater than max
        if current > max {
            return nil
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
