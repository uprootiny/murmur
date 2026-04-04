import XCTest
@testable import MurmurCore

final class TimelineModelTests: XCTestCase {

    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MurmurTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testEmptyTimelineHasZeroDuration() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 10, chunkDuration: 5)
        let model = TimelineModel(ringBuffer: buffer)
        XCTAssertEqual(model.totalDuration, 0)
        XCTAssertTrue(model.chunks.isEmpty)
    }

    func testReloadUpdatesChunks() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 10, chunkDuration: 5)
        let model = TimelineModel(ringBuffer: buffer)

        // Write a chunk
        let url = buffer.nextChunkURL()
        try? "audio data".data(using: .utf8)?.write(to: url)
        buffer.advanceIndex()

        let expectation = XCTestExpectation(description: "reload")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            model.reload()
            XCTAssertEqual(model.chunks.count, 1)
            XCTAssertEqual(model.totalDuration, 5.0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testTotalDurationScalesWithChunks() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 100, chunkDuration: 10)
        let model = TimelineModel(ringBuffer: buffer)

        for _ in 0..<5 {
            let url = buffer.nextChunkURL()
            try? "data".data(using: .utf8)?.write(to: url)
            buffer.advanceIndex()
        }

        let expectation = XCTestExpectation(description: "scale")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            model.reload()
            XCTAssertEqual(model.totalDuration, 50.0) // 5 chunks * 10 sec
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }
}
