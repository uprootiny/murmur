import XCTest
@testable import MurmurCore

final class RingBufferTests: XCTestCase {

    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MurmurTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeChunkFile(at url: URL, content: String = "test") {
        try? content.data(using: .utf8)?.write(to: url)
    }

    // MARK: - Empty buffer

    func testEmptyBufferHasZeroChunks() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 3, chunkDuration: 5)
        XCTAssertEqual(buffer.chunkCount, 0)
    }

    func testLatestChunksEmptyBuffer() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 3, chunkDuration: 5)
        XCTAssertTrue(buffer.latestChunks(windowSeconds: 10).isEmpty)
    }

    func testOrderedChunksEmptyBuffer() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 3, chunkDuration: 5)
        XCTAssertTrue(buffer.orderedChunks().isEmpty)
    }

    // MARK: - Chunk URL generation

    func testNextChunkURLCreatesPath() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 3, chunkDuration: 5)
        let url = buffer.nextChunkURL(fileExtension: "m4a")
        XCTAssertEqual(url.pathExtension, "m4a")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("chunk_"))
    }

    func testNextChunkURLWrapsAround() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 3, chunkDuration: 5)

        // Generate 4 URLs (should wrap at 3)
        let url0 = buffer.nextChunkURL()
        buffer.advanceIndex()
        let url1 = buffer.nextChunkURL()
        buffer.advanceIndex()
        let url2 = buffer.nextChunkURL()
        buffer.advanceIndex()
        let url3 = buffer.nextChunkURL()

        XCTAssertTrue(url0.lastPathComponent.contains("000"))
        XCTAssertTrue(url1.lastPathComponent.contains("001"))
        XCTAssertTrue(url2.lastPathComponent.contains("002"))
        // Wraps back to 000
        XCTAssertTrue(url3.lastPathComponent.contains("000"))
    }

    // MARK: - Advance and count

    func testAdvanceIndexIncrementsCount() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 10, chunkDuration: 5)

        let url = buffer.nextChunkURL()
        writeChunkFile(at: url)
        buffer.advanceIndex()

        // Give the async queue a moment
        let expectation = XCTestExpectation(description: "advance")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(buffer.chunkCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testChunkCountCapsAtMax() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 3, chunkDuration: 5)

        for _ in 0..<5 {
            let url = buffer.nextChunkURL()
            writeChunkFile(at: url)
            buffer.advanceIndex()
        }

        let expectation = XCTestExpectation(description: "cap")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(buffer.chunkCount, 3)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    // MARK: - Clear

    func testClearRemovesAllChunks() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 3, chunkDuration: 5)

        for _ in 0..<3 {
            let url = buffer.nextChunkURL()
            writeChunkFile(at: url)
            buffer.advanceIndex()
        }

        let expectation = XCTestExpectation(description: "clear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            buffer.clear()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertEqual(buffer.chunkCount, 0)
                XCTAssertTrue(buffer.orderedChunks().isEmpty)
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2)
    }

    // MARK: - Latest chunks windowing

    func testLatestChunksReturnsCorrectWindow() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 10, chunkDuration: 5)

        for _ in 0..<6 {
            let url = buffer.nextChunkURL()
            writeChunkFile(at: url)
            buffer.advanceIndex()
        }

        let expectation = XCTestExpectation(description: "window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // 10 seconds window / 5 second chunks = 2 chunks max
            let latest = buffer.latestChunks(windowSeconds: 10)
            XCTAssertEqual(latest.count, 2)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    // MARK: - Duration

    func testChunkDurationSeconds() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 10, chunkDuration: 7)
        XCTAssertEqual(buffer.chunkDurationSeconds, 7)
    }

    // MARK: - Directory creation

    func testInitCreatesDirectory() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MurmurTests-\(UUID().uuidString)")
            .appendingPathComponent("nested/deep")
        _ = RingBuffer(directory: dir, maxChunks: 3, chunkDuration: 5)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }
}
