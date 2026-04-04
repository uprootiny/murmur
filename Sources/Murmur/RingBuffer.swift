import Foundation

/// Manages a bounded directory of numbered media chunk files.
///
/// Key invariant: total disk usage never exceeds `maxDiskBytes`.
/// When the buffer is full the oldest chunk is overwritten.
///
/// File naming: `chunk_000.mp4`, `chunk_001.m4a`, etc.
final class RingBuffer: ObservableObject {
    // MARK: - Configuration

    let directory: URL
    let maxChunks: Int
    let chunkDurationSeconds: TimeInterval
    let maxDiskBytes: UInt64

    // MARK: - Published State

    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var chunkCount: Int = 0

    // MARK: - Private

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.uprootiny.murmur.ringbuffer", qos: .utility)

    // MARK: - Init

    /// - Parameters:
    ///   - directory: Folder where chunk files are stored.
    ///   - maxChunks: Maximum number of chunk slots (e.g. 360).
    ///   - chunkDurationSeconds: Nominal duration of each chunk (e.g. 10).
    ///   - maxDiskBytes: Hard ceiling on total disk usage. Default 1 GB.
    init(
        directory: URL,
        maxChunks: Int = 360,
        chunkDurationSeconds: TimeInterval = 10,
        maxDiskBytes: UInt64 = 1_073_741_824
    ) {
        self.directory = directory
        self.maxChunks = maxChunks
        self.chunkDurationSeconds = chunkDurationSeconds
        self.maxDiskBytes = maxDiskBytes

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.chunkCount = existingChunkFiles().count
    }

    // MARK: - Public API

    /// Total buffered duration based on chunk count.
    var totalDuration: TimeInterval {
        return Double(chunkCount) * chunkDurationSeconds
    }

    /// Human-readable buffered time, e.g. "42 min".
    var formattedDuration: String {
        let minutes = Int(totalDuration) / 60
        if minutes < 1 {
            let seconds = Int(totalDuration)
            return "\(seconds) sec"
        }
        return "\(minutes) min"
    }

    /// Current disk usage of the chunk directory in bytes.
    var diskUsage: UInt64 {
        let files = existingChunkFiles()
        var total: UInt64 = 0
        for file in files {
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }

    /// Human-readable disk usage.
    var formattedDiskUsage: String {
        let bytes = diskUsage
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Returns the URL for the next chunk to write.
    /// If the buffer is full, this overwrites the oldest slot.
    func nextChunkURL(extension ext: String = "mp4") -> URL {
        // Enforce disk budget -- evict oldest chunks while over budget
        enforceStorageBudget()

        let index = currentIndex % maxChunks
        let filename = String(format: "chunk_%03d.%@", index, ext)
        let url = directory.appendingPathComponent(filename)

        // Remove existing file at this slot if present
        try? fileManager.removeItem(at: url)

        return url
    }

    /// Call after a chunk has been fully written to advance the index.
    func advanceIndex() {
        DispatchQueue.main.async {
            self.currentIndex += 1
            self.chunkCount = min(self.chunkCount + 1, self.maxChunks)
        }
    }

    /// Returns the URL for a chunk at a given ring slot, or nil if it does not exist.
    func chunkURL(at slot: Int, extension ext: String = "mp4") -> URL? {
        let filename = String(format: "chunk_%03d.%@", slot, ext)
        let url = directory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Returns all existing chunk URLs in order from oldest to newest.
    func orderedChunks() -> [URL] {
        guard chunkCount > 0 else { return [] }

        var result: [URL] = []
        let total = min(chunkCount, maxChunks)
        let startSlot = (currentIndex - total + maxChunks) % maxChunks

        for i in 0..<total {
            let slot = (startSlot + i) % maxChunks
            if let url = existingChunkAtSlot(slot) {
                result.append(url)
            }
        }
        return result
    }

    /// Removes all chunk files and resets state.
    func clear() {
        let files = existingChunkFiles()
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        DispatchQueue.main.async {
            self.currentIndex = 0
            self.chunkCount = 0
        }
    }

    // MARK: - Private Helpers

    private func existingChunkFiles() -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        return contents.filter { $0.lastPathComponent.hasPrefix("chunk_") }
    }

    private func existingChunkAtSlot(_ slot: Int) -> URL? {
        let prefix = String(format: "chunk_%03d", slot)
        return existingChunkFiles().first { $0.lastPathComponent.hasPrefix(prefix) }
    }

    /// Evict oldest chunks until disk usage is under the budget.
    private func enforceStorageBudget() {
        var usage = diskUsage
        guard usage > maxDiskBytes else { return }

        let ordered = orderedChunks()
        for file in ordered {
            guard usage > maxDiskBytes else { break }
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? UInt64 {
                try? fileManager.removeItem(at: file)
                usage -= size
                DispatchQueue.main.async {
                    self.chunkCount = max(self.chunkCount - 1, 0)
                }
            }
        }
    }
}
