import AppKit
import Foundation

enum TibiaAsset: String, CaseIterable, Sendable {
    case stoneBackground
    case titleBar
    case frameOuter
    case panelFrame
    case fieldFrame
    case buttonFrame
    case buttonPressedFrame
    case tabFrame
    case tabSelectedFrame
    case slotFrame
    case checkboxOff
    case checkboxOn
    case progressTrack
    case progressFillHP
    case progressFillMana
    case iconHP
    case iconMana
    case iconStatus
    case iconPermissions
    case iconRegion
    case iconHealing
    case iconCombo
    case iconHaste
    case iconEating
    case iconSkinning

    var fileName: String {
        "\(rawValue).png"
    }

    var retinaFileName: String {
        "\(rawValue)@2x.png"
    }
}

enum TibiaSkin {
    private static let resourceSubdirectory = "TibiaSkin"
    private static let imageCache = NSCache<NSString, NSImage>()

    static func image(for asset: TibiaAsset) -> NSImage? {
        let cacheKey = asset.rawValue as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard
            let standardURL = url(for: asset, scale: 1),
            let retinaURL = url(for: asset, scale: 2),
            let standardData = try? Data(contentsOf: standardURL),
            let retinaData = try? Data(contentsOf: retinaURL),
            let standardRepresentation = NSBitmapImageRep(data: standardData),
            let retinaRepresentation = NSBitmapImageRep(data: retinaData)
        else {
            return nil
        }

        let logicalSize = NSSize(
            width: standardRepresentation.pixelsWide,
            height: standardRepresentation.pixelsHigh
        )
        standardRepresentation.size = logicalSize
        retinaRepresentation.size = logicalSize

        let image = NSImage(size: logicalSize)
        image.addRepresentation(standardRepresentation)
        image.addRepresentation(retinaRepresentation)
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    static func url(for asset: TibiaAsset, scale: Int) -> URL? {
        guard scale == 1 || scale == 2 else {
            return nil
        }

        let suffix = scale == 2 ? "@2x" : ""
        let resourceName = asset.rawValue + suffix

        if let mainBundleURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: resourceSubdirectory
        ) {
            return mainBundleURL
        }

        #if SWIFT_PACKAGE
        return Bundle.module.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: resourceSubdirectory
        )
        #else
        return nil
        #endif
    }
}
