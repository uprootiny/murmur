import XCTest
@testable import MurmurCore

final class MurmurLoggerTests: XCTestCase {

    func testLoggerIsSingleton() {
        let a = MurmurLogger.shared
        let b = MurmurLogger.shared
        XCTAssertTrue(a === b)
    }

    func testLogDoesNotCrash() {
        // Smoke test: logging should not throw or crash
        MurmurLogger.shared.log("test message from unit test")
    }
}
