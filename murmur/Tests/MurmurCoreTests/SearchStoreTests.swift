import XCTest
@testable import MurmurCore

final class SearchStoreTests: XCTestCase {
    func testInsertAndSearchOCR() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbURL = tempDir.appendingPathComponent("search.sqlite")

        let store = SearchStore(databaseURL: dbURL)
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        store.insertOCRText(timestamp: ts, chunkID: 1, text: "hello world")

        let results = waitForResults(store: store, query: "hello")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.type, .ocr)
    }

    private func waitForResults(store: SearchStore, query: String) -> [SearchResult] {
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            let results = store.search(query: query)
            if !results.isEmpty {
                return results
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return []
    }
}
