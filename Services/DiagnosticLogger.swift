import Foundation

enum DiagnosticLogValue: Encodable, Sendable {
    case bool(Bool)
    case double(Double)
    case integer(Int)
    case string(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

protocol DiagnosticLogging: AnyObject {
    func log(_ event: String, fields: [String: DiagnosticLogValue])
}

final class PixelBotDiagnosticLogger: DiagnosticLogging, @unchecked Sendable {
    static let shared = PixelBotDiagnosticLogger()

    private let queue: DispatchQueue
    private let directoryURL: URL
    private let maximumFileSize: Int
    private let encoder = JSONEncoder()
    private let dateFormatter = ISO8601DateFormatter()
    private let fileManager: FileManager

    private var currentURL: URL {
        directoryURL.appendingPathComponent("runtime.jsonl")
    }

    private var previousURL: URL {
        directoryURL.appendingPathComponent("runtime.previous.jsonl")
    }

    init(
        directoryURL: URL? = nil,
        maximumFileSize: Int = 1_048_576,
        queue: DispatchQueue = DispatchQueue(
            label: "com.pixelbot.diagnostic-log",
            qos: .utility
        ),
        fileManager: FileManager = .default
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.directoryURL = applicationSupport
                .appendingPathComponent("PixelBot")
                .appendingPathComponent("Logs")
        }
        self.maximumFileSize = max(1, maximumFileSize)
        self.queue = queue
        self.fileManager = fileManager
        encoder.outputFormatting = [.sortedKeys]
    }

    func log(_ event: String, fields: [String: DiagnosticLogValue] = [:]) {
        let timestamp = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            guard let self else { return }
            self.write(event: event, wallTime: self.dateFormatter.string(from: timestamp), uptime: uptime, fields: fields)
        }
    }

    func flush() {
        queue.sync {}
    }

    private func write(
        event: String,
        wallTime: String,
        uptime: TimeInterval,
        fields: [String: DiagnosticLogValue]
    ) {
        var record = fields
        record["event"] = .string(event)
        record["timestamp"] = .string(wallTime)
        record["uptime"] = .double(uptime)

        do {
            var data = try encoder.encode(record)
            data.append(0x0A)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try rotateIfNeeded(adding: data.count)

            if !fileManager.fileExists(atPath: currentURL.path) {
                try data.write(to: currentURL, options: .atomic)
                return
            }

            let handle = try FileHandle(forWritingTo: currentURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            print("Failed to write diagnostic log: \(error)")
        }
    }

    private func rotateIfNeeded(adding byteCount: Int) throws {
        let attributes = try? fileManager.attributesOfItem(atPath: currentURL.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize > 0, currentSize + byteCount > maximumFileSize else { return }

        if fileManager.fileExists(atPath: previousURL.path) {
            try fileManager.removeItem(at: previousURL)
        }
        try fileManager.moveItem(at: currentURL, to: previousURL)
    }
}

/// Cumulative measurements, kept off the per-frame disk logging path.
final class DiagnosticMetrics: @unchecked Sendable {
    enum Counter: String, CaseIterable, Sendable {
        case recognitionFailures
        case recognitionFallbacks
        case cacheHits
        case droppedFrames
        case invalidFrameTiming
    }

    static let shared = DiagnosticMetrics()
    private let lock = NSLock()
    private var counters: [Counter: Int] = [:]
    private var latencyCount = 0
    private var latencyTotal: TimeInterval = 0
    private var latencyMaximum: TimeInterval = 0

    func record(_ counter: Counter) {
        lock.lock()
        defer { lock.unlock() }
        counters[counter, default: 0] += 1
    }

    func recordCaptureToKeyDown(seconds: TimeInterval) {
        guard seconds.isFinite, seconds >= 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        latencyCount += 1
        latencyTotal += seconds
        latencyMaximum = max(latencyMaximum, seconds)
    }

    func snapshot() -> [String: DiagnosticLogValue] {
        lock.lock()
        defer { lock.unlock() }
        var fields = Dictionary(uniqueKeysWithValues: Counter.allCases.map {
            ($0.rawValue, DiagnosticLogValue.integer(counters[$0, default: 0]))
        })
        fields["captureToKeyDownCount"] = .integer(latencyCount)
        fields["captureToKeyDownMeanMs"] = .double(latencyCount > 0 ? latencyTotal * 1000 / Double(latencyCount) : 0)
        fields["captureToKeyDownMaximumMs"] = .double(latencyMaximum * 1000)
        return fields
    }
}
