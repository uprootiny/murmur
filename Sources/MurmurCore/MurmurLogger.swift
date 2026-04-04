import Foundation

public final class MurmurLogger {
    public static let shared = MurmurLogger()

    public enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let queue = DispatchQueue(label: "com.murmur.logger", qos: .utility)
    private let fileURL: URL
    private let maxBytes: UInt64 = 5 * 1024 * 1024

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Murmur/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("murmur.log")
    }

    public func log(_ message: String, level: Level = .info, category: String = "core") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] [\(category)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                self.rotateIfNeeded()
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    if let handle = FileHandle(forWritingAtPath: self.fileURL.path) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.fileURL, options: .atomic)
                }
            }
        }
        print(line.trimmingCharacters(in: .newlines))
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64,
              size >= maxBytes else { return }

        let rotated = fileURL.deletingLastPathComponent().appendingPathComponent("murmur.log.1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: fileURL, to: rotated)
    }
}
