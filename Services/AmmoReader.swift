import Foundation
import CoreGraphics
import Vision

class AmmoReader {
    
    var debugMode = false
    
    private var region: CGRect?
    private var lastAmmoValue: Int?
    private var currentAmmoValue: Int?
    private var lastImageHash: Int = 0
    
    // Reuse the request to avoid overhead
    private lazy var recognitionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.1
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        return request
    }()
    
    func setRegion(_ rect: (x: Int, y: Int, width: Int, height: Int)) {
        region = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        lastAmmoValue = nil
        currentAmmoValue = nil
        lastImageHash = 0
        if debugMode {
            print("🏹 Ammo region set: (x: \(rect.x), y: \(rect.y), width: \(rect.width), height: \(rect.height))")
        }
    }
    
    func hasValidRegion() -> Bool {
        return region != nil
    }
    
    func readAmmo(from screenImage: CGImage) {
        guard let region = region else { return }
        
        let x = Int(region.origin.x)
        let y = Int(region.origin.y)
        let width = Int(region.size.width)
        let height = Int(region.size.height)
        
        guard x >= 0 && y >= 0 && 
              x + width <= screenImage.width && 
              y + height <= screenImage.height else {
            return
        }
        
        guard let croppedImage = screenImage.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else {
            return
        }
        
        // OPTIMIZATION: Check if image changed using a fast hash before running expensive OCR
        let currentHash = computeFastHash(croppedImage)
        if currentHash == lastImageHash {
            // Image is identical to last frame, no need to re-run OCR
            return
        }
        lastImageHash = currentHash
        
        if let ammo = performOCR(on: croppedImage, label: debugMode ? "Ammo" : nil) {
            lastAmmoValue = currentAmmoValue
            currentAmmoValue = ammo
            
            if debugMode {
                 if let last = lastAmmoValue, let current = currentAmmoValue, last != current {
                     print("🏹 Ammo changed: \(last) → \(current)")
                 } else if lastAmmoValue == nil {
                     print("🏹 Ammo initial: \(ammo)")
                 }
            }
        }
    }
    
    func checkAmmoDecrease() -> Bool {
        guard let last = lastAmmoValue, let current = currentAmmoValue else {
            return false
        }
        let isValid = current >= 0 && current <= 2000 && last >= 0 && last <= 2000
        return isValid && current < last
    }
    
    func reset() {
        lastAmmoValue = nil
        currentAmmoValue = nil
        lastImageHash = 0
    }
    
    private func computeFastHash(_ image: CGImage) -> Int {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data else {
            return 0
        }
        // Simple hash of raw bytes
        let pointer = CFDataGetBytePtr(data)!
        let length = CFDataGetLength(data)
        
        var hash = 5381
        // Skipping bytes for speed is fine for detecting if screen changed
        // Step 4 = check every pixel (since 4 bytes per pixel) roughly
        let step = 4 
        
        for i in stride(from: 0, to: length, by: step) {
            hash = ((hash << 5) &+ hash) &+ Int(pointer[i])
        }
        return hash
    }
    
    private func preprocessImage(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        
        // Scale up
        let scale = 6 // Reduced from 8 to 6 for slight perf gain, usually enough
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
        var outputData = [UInt8](repeating: 255, count: length)
        
        // COLOR FILTERING
        // Target: RGB(191, 191, 191) with tolerance
        
        for i in stride(from: 0, to: length, by: 4) {
            let r = Int(pointer[i])
            let g = Int(pointer[i + 1])
            let b = Int(pointer[i + 2])
            
            let isTargetGray = abs(r - 191) < 40 && 
                               abs(g - 191) < 40 && 
                               abs(b - 191) < 40 &&
                               abs(r - g) < 20 &&
                               abs(g - b) < 20
            
            if isTargetGray {
                outputData[i] = 0
                outputData[i + 1] = 0
                outputData[i + 2] = 0
                outputData[i + 3] = 255
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
    
    private func performOCR(on image: CGImage, label: String? = nil) -> Int? {
        let processedImage = preprocessImage(image)
        let handler = VNImageRequestHandler(cgImage: processedImage, options: [:])
        
        do {
            try handler.perform([recognitionRequest])
            
            guard let results = recognitionRequest.results, !results.isEmpty else {
                if let label = label {
                    /* print("🔍 \(label) OCR: No results") */
                }
                return nil
            }
            
            var allTexts: [String] = []
            for observation in results {
                if let text = observation.topCandidates(1).first?.string {
                    allTexts.append(text)
                }
            }
            
            if let label = label {
                /* print("🔍 \(label) OCR raw: \(allTexts)") */
            }
            
            for text in allTexts {
                let cleaned = text
                    .replacingOccurrences(of: "O", with: "0")
                    .replacingOccurrences(of: "o", with: "0")
                    .replacingOccurrences(of: "I", with: "1")
                    .replacingOccurrences(of: "l", with: "1")
                    .replacingOccurrences(of: "i", with: "1")
                    .replacingOccurrences(of: "B", with: "8")
                    .replacingOccurrences(of: "S", with: "5")
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: " ", with: "")
                
                let digits = cleaned.filter { $0.isNumber }
                
                if let value = Int(digits) {
                    if let label = label {
                        /* print("✅ \(label) parsed: \(value)") */
                    }
                    return value
                }
            }
            
            return nil
            
        } catch {
            return nil
        }
    }
}
