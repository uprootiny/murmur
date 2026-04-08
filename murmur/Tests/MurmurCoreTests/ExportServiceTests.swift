import XCTest
@testable import MurmurCore

final class ExportServiceTests: XCTestCase {

    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MurmurTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testExportEmptyBufferReturnsError() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 10, chunkDuration: 5)
        let exporter = ExportService(ringBuffer: buffer)

        let expectation = XCTestExpectation(description: "empty export")
        let destDir = makeTempDir()

        exporter.exportLatest(windowSeconds: 10, to: destDir) { result in
            switch result {
            case .success:
                XCTFail("Expected failure for empty buffer")
            case .failure:
                break // expected
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testExportCreatesManifest() {
        let dir = makeTempDir()
        let buffer = RingBuffer(directory: dir, maxChunks: 10, chunkDuration: 5)

        // Write some chunks
        for _ in 0..<3 {
            let url = buffer.nextChunkURL()
            try? "fake audio data".data(using: .utf8)?.write(to: url)
            buffer.advanceIndex()
        }

        let exporter = ExportService(ringBuffer: buffer)
        let destDir = makeTempDir()

        let expectation = XCTestExpectation(description: "export manifest")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exporter.exportLatest(windowSeconds: 15, to: destDir) { result in
                switch result {
                case .success(let folder):
                    let manifest = folder.appendingPathComponent("manifest.csv")
                    XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
                    if let content = try? String(contentsOf: manifest, encoding: .utf8) {
                        let lines = content.split(separator: "\n")
                        XCTAssertEqual(lines.count, 3)
                    }
                case .failure(let error):
                    XCTFail("Export failed: \(error)")
                }
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 5)
    }
}
