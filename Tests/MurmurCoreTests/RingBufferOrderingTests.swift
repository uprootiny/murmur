import XCTest
@testable import MurmurCore

final class RingBufferOrderingTests: XCTestCase {
    func testOrderedChunksWrapCorrectly() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let buffer = RingBuffer(directory: tempDir, maxChunks: 3, chunkDuration: 5)

        for _ in 0..<3 {
            let url = buffer.nextChunkURL(fileExtension: "m4a")
            try? "test".data(using: .utf8)?.write(to: url)
            buffer.advanceIndex()
        }

        XCTAssertTrue(waitForChunkCount(buffer, expected: 3))
        XCTAssertEqual(buffer.orderedChunks().map { $0.url.lastPathComponent }, [
            "chunk_000.m4a",
            "chunk_001.m4a",
            "chunk_002.m4a"
        ])

        let url = buffer.nextChunkURL(fileExtension: "m4a")
        try? "test".data(using: .utf8)?.write(to: url)
        buffer.advanceIndex()

        XCTAssertTrue(waitForChunkCount(buffer, expected: 3))
        XCTAssertEqual(buffer.orderedChunks().map { $0.url.lastPathComponent }, [
            "chunk_001.m4a",
            "chunk_002.m4a",
            "chunk_000.m4a"
        ])
    }

    private func waitForChunkCount(_ buffer: RingBuffer, expected: Int) -> Bool {
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if buffer.chunkCount == expected {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }
}
