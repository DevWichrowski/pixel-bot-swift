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
            exclude: [
                "Package.swift",
                "Info.plist",
                "PixelBot.entitlements",
                "PixelBot Dev.app",
                "README.md",
                "AGENTS.md",
                "CLAUDE.md",
                "AppIcon.png",
                "AppIconDev.png",
                "build_app.sh",
                "bot_log.txt",
                "bot_debug.txt",
                "Tests",
                "test_healer.swift",
                "test_combo.swift",
                "test_cooldowns.swift",
                "test_random_cooldowns.swift",
                "test_paladin_combo.swift",
                "test_reaction_delay.swift",
                "test_spirit_potion.swift",
            ],
            sources: [
                "App/PixelBotApp.swift",
                "Models/OCRModels.swift",
                "Models/StatusReading.swift",
                "Models/HealConfig.swift",
                "Models/UserConfig.swift",
                "Services/HumanRandom.swift",
                "Services/DiagnosticLogger.swift",
                "Services/ConfigManager.swift",
                "Services/KeyPressService.swift",
                "Services/ScreenCaptureService.swift",
                "Services/OCRPipeline.swift",
                "Services/HPManaReader.swift",
                "Services/AmmoReader.swift",
                "Services/RegionSelector.swift",
                "Features/AutoHealer.swift",
                "Features/AutoEater.swift",
                "Features/AutoHaste.swift",
                "Features/AutoSkinner.swift",
                "Features/AutoCombo.swift",
                "Views/TibiaSkin.swift",
                "Views/PixelArtComponents.swift",
                "Views/StatusView.swift",
                "Views/ConfigView.swift",
                "Views/PresetsView.swift",
                "Views/OverlayView.swift",
                "Bot/TibiaBot.swift"
            ],
            resources: [
                .copy("Resources/TibiaSkin")
            ]
        ),
        .testTarget(
            name: "PixelBotTests",
            dependencies: ["PixelBot"],
            path: "Tests/PixelBotTests"
        )
    ]
)
