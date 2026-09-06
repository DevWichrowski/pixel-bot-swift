import Foundation

/// Manages loading and saving user configuration to JSON.
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: UserConfig

    private final class SaveRequest {
        let data: Data

        private let lock = NSLock()
        private var cancelled = false

        init(data: Data) {
            self.data = data
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        var shouldRun: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !cancelled
        }
    }

    private let configURL: URL
    private let debounceInterval: TimeInterval
    private let fileQueue: DispatchQueue
    private let writeData: (Data, URL) throws -> Void
    private let pendingLock = NSLock()
    private var pendingSave: SaveRequest?

    init(
        configURL: URL? = nil,
        debounceInterval: TimeInterval = 0.3,
        fileQueue: DispatchQueue = DispatchQueue(label: "com.pixelbot.config-file", qos: .utility),
        writeData: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        if let configURL {
            self.configURL = configURL
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.configURL = appSupport
                .appendingPathComponent("PixelBot")
                .appendingPathComponent("user_config.json")
        }

        self.debounceInterval = debounceInterval
        self.fileQueue = fileQueue
        self.writeData = writeData
        config = UserConfig()

        do {
            try FileManager.default.createDirectory(
                at: self.configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            print("Failed to create config directory: \(error)")
        }

        load()
    }

    deinit {
        cancelPendingSave()
    }

    /// Loads configuration synchronously during application hydration.
    func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            print("No config file, using defaults")
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(UserConfig.self, from: data)
            print("Config loaded from \(configURL.path)")
        } catch {
            print("Failed to load config: \(error)")
            config = UserConfig()
        }
    }

    /// Encodes a stable snapshot and writes only the latest request after 300 ms.
    func save() {
        let data: Data
        do {
            data = try JSONEncoder().encode(config)
        } catch {
            print("Failed to encode config: \(error)")
            return
        }

        let request = SaveRequest(data: data)
        replacePendingSave(with: request)

        fileQueue.asyncAfter(deadline: .now() + debounceInterval) { [weak self, request] in
            guard let self, request.shouldRun else { return }

            do {
                try self.writeData(request.data, self.configURL)
                self.clearPendingSave(ifMatching: request)
                print("Config saved")
            } catch {
                self.clearPendingSave(ifMatching: request)
                print("Failed to save config: \(error)")
            }
        }
    }

    /// Cancels a debounced write before removing the persisted configuration.
    func reset() {
        cancelPendingSave()
        config = UserConfig()

        fileQueue.sync {
            do {
                if FileManager.default.fileExists(atPath: configURL.path) {
                    try FileManager.default.removeItem(at: configURL)
                }
                print("Config reset to defaults")
            } catch {
                print("Failed to remove config: \(error)")
            }
        }
    }

    /// Finish the latest configuration write before application termination.
    func flush() {
        cancelPendingSave()
        do {
            let data = try JSONEncoder().encode(config)
            try fileQueue.sync { try writeData(data, configURL) }
        } catch { print("Failed to flush config: \(error)") }
    }

    func cancelPendingSave() {
        pendingLock.lock()
        let request = pendingSave
        pendingSave = nil
        pendingLock.unlock()
        request?.cancel()
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

    func setAmmoRegion(_ region: (x: Int, y: Int, width: Int, height: Int)) {
        config.regions.ammoRegion = [region.x, region.y, region.width, region.height]
        save()
    }

    var isConfigured: Bool {
        config.regions.isFullyConfigured
    }

    private func replacePendingSave(with request: SaveRequest) {
        pendingLock.lock()
        let previous = pendingSave
        pendingSave = request
        pendingLock.unlock()
        previous?.cancel()
    }

    private func clearPendingSave(ifMatching request: SaveRequest) {
        pendingLock.lock()
        if pendingSave === request {
            pendingSave = nil
        }
        pendingLock.unlock()
    }
}
