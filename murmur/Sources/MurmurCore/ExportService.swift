import Foundation

public final class ExportService {
    public enum ExportError: Error {
        case noChunks
        case destinationMissing
    }

    private let ringBuffer: RingBuffer
    private let queue = DispatchQueue(label: "com.murmur.export", qos: .utility)

    public init(ringBuffer: RingBuffer) {
        self.ringBuffer = ringBuffer
    }

    /// Exports the latest window into a folder as chunk files plus a manifest.
    /// This avoids blocking capture and keeps export logic out of UI.
    public func exportLatest(windowSeconds: TimeInterval,
                             to destinationFolder: URL,
                             completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            let chunks = self.ringBuffer.latestChunks(windowSeconds: windowSeconds)
            guard !chunks.isEmpty else {
                completion(.failure(ExportError.noChunks))
                return
            }

            let folder = destinationFolder.appendingPathComponent("MurmurExport_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var manifestLines: [String] = []
                for (idx, chunk) in chunks.enumerated() {
                    let dest = folder.appendingPathComponent(String(format: "chunk_%03d.m4a", idx))
                    try FileManager.default.copyItem(at: chunk.url, to: dest)
                    manifestLines.append("\(idx),\(chunk.startTime.timeIntervalSince1970),\(chunk.duration),\(dest.lastPathComponent)")
                }
                let manifest = folder.appendingPathComponent("manifest.csv")
                try manifestLines.joined(separator: "\n").write(to: manifest, atomically: true, encoding: .utf8)
                completion(.success(folder))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
