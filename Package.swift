// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PixelBot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PixelBot", targets: ["PixelBot"])
    ],
    targets: [
        .executableTarget(
            name: "PixelBot",
            path: ".",
            exclude: ["Package.swift", "Info.plist", "PixelBot.entitlements", "README.md"],
            sources: [
                "App/PixelBotApp.swift",
                "Models/StatusReading.swift",
                "Models/HealConfig.swift",
                "Models/UserConfig.swift",
                "Services/ConfigManager.swift",
                "Services/KeyPressService.swift",
                "Services/ScreenCaptureService.swift",
                "Services/HPManaReader.swift",
                "Services/RegionSelector.swift",
                "Features/AutoHealer.swift",
                "Features/AutoEater.swift",
                "Features/AutoHaste.swift",
                "Features/AutoSkinner.swift",
                "Views/PixelArtComponents.swift",
                "Views/StatusView.swift",
                "Views/ConfigView.swift",
                "Views/OverlayView.swift",
                "Bot/TibiaBot.swift"
            ]
        )
    ]
)

