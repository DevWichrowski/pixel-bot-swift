import Foundation

/// Manages loading and saving user configuration to JSON
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var config: UserConfig
    
    private let configURL: URL
    
    init() {
        // Use Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("PixelBot")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        configURL = appFolder.appendingPathComponent("user_config.json")
        config = UserConfig()
        
        load()
    }
    
    /// Load configuration from disk
    func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            print("📁 No config file, using defaults")
            return
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(UserConfig.self, from: data)
            print("✅ Config loaded from \(configURL.path)")
        } catch {
            print("⚠️ Failed to load config: \(error)")
            config = UserConfig()
        }
    }
    
    /// Save configuration to disk
    func save() {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            print("✅ Config saved")
        } catch {
            print("❌ Failed to save config: \(error)")
        }
    }
    
    /// Reset configuration to defaults
    func reset() {
        config = UserConfig()
        try? FileManager.default.removeItem(at: configURL)
        print("🔄 Config reset to defaults")
    }
    
    // MARK: - Convenience setters
    
    func setHPRegion(_ region: (x: Int, y: Int, width: Int, height: Int)) {
        config.regions.hpRegion = [region.x, region.y, region.width, region.height]
        save()
    }
    
    func setManaRegion(_ region: (x: Int, y: Int, width: Int, height: Int)) {
        config.regions.manaRegion = [region.x, region.y, region.width, region.height]
        save()
    }
    
    var isConfigured: Bool {
        config.regions.isFullyConfigured
    }
}
