import Foundation

// Ring buffer is the source of truth; chunks are atomic and replaceable at slot overwrite.
public final class RingBuffer {
    public struct Chunk: Equatable {
        public let id: UUID
        public let startTime: Date
        public let duration: TimeInterval
        public let url: URL
        public let sizeBytes: UInt64
    }

    public let directory: URL
    public let maxChunks: Int
    public let chunkDuration: TimeInterval
    public let maxDiskBytes: UInt64

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.murmur.ringbuffer", qos: .utility)
    private var currentIndex: Int = 0
    private var storedChunkCount: Int = 0

    public init(directory: URL,
                maxChunks: Int = 360,
                chunkDuration: TimeInterval = 10,
                maxDiskBytes: UInt64 = 1_073_741_824) {
        self.directory = directory
        self.maxChunks = maxChunks
        self.chunkDuration = chunkDuration
        self.maxDiskBytes = maxDiskBytes
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storedChunkCount = existingChunkFiles().count
    }

    public var chunkCount: Int {
        queue.sync { storedChunkCount }
    }

    public var chunkDurationSeconds: TimeInterval {
        chunkDuration
    }

    public func nextChunkURL(fileExtension: String = "m4a") -> URL {
        enforceStorageBudget()
        let index = queue.sync { currentIndex % maxChunks }
        let filename = String(format: "chunk_%03d.%@", index, fileExtension)
        let url = directory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
        return url
    }

    public func advanceIndex() {
        queue.async {
            self.currentIndex += 1
            self.storedChunkCount = min(self.storedChunkCount + 1, self.maxChunks)
        }
    }

    public func orderedChunks() -> [Chunk] {
        let snapshot = queue.sync { (currentIndex, storedChunkCount) }
        let total = min(snapshot.1, maxChunks)
        guard total > 0 else { return [] }
        let startSlot = (snapshot.0 - total + maxChunks) % maxChunks
        let end = Date()
        let start = end.addingTimeInterval(-Double(total) * chunkDuration)

        var result: [Chunk] = []
        for i in 0..<total {
            let slot = (startSlot + i) % maxChunks
            let filename = String(format: "chunk_%03d.m4a", slot)
            let url = directory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let attrs = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
            let size = attrs[.size] as? UInt64 ?? 0
            let startTime = start.addingTimeInterval(Double(i) * chunkDuration)
            result.append(Chunk(id: UUID(), startTime: startTime, duration: chunkDuration, url: url, sizeBytes: size))
        }
        return result
    }

    public func latestChunks(windowSeconds: TimeInterval) -> [Chunk] {
        let chunks = orderedChunks()
        guard !chunks.isEmpty else { return [] }
        let maxCount = max(Int(ceil(windowSeconds / chunkDuration)), 1)
        return Array(chunks.suffix(maxCount))
    }

    public func clear() {
        let files = existingChunkFiles()
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        queue.async {
            self.currentIndex = 0
            self.storedChunkCount = 0
        }
    }

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

    private func enforceStorageBudget() {
        var usage = diskUsage()
        guard usage > maxDiskBytes else { return }
        let ordered = existingChunkFiles().sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in ordered {
            guard usage > maxDiskBytes else { break }
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? UInt64 {
                try? fileManager.removeItem(at: file)
                usage -= size
            }
        }
    }

    private func diskUsage() -> UInt64 {
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
}
