import XCTest
@testable import HoverMind

final class KeychainHelperTests: XCTestCase {

    func testSaveAndLoad() {
        let key = "test_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: key) }
        XCTAssertTrue(KeychainHelper.save(key: key, value: "secret123"))
        XCTAssertEqual(KeychainHelper.load(key: key), "secret123")
    }

    func testLoadMissing() {
        XCTAssertNil(KeychainHelper.load(key: "nonexistent_\(UUID().uuidString)"))
    }

    func testDelete() {
        let key = "test_del_\(UUID().uuidString)"
        KeychainHelper.save(key: key, value: "temp")
        KeychainHelper.delete(key: key)
        XCTAssertNil(KeychainHelper.load(key: key))
    }

    func testOverwrite() {
        let key = "test_ow_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: key) }
        KeychainHelper.save(key: key, value: "first")
        KeychainHelper.save(key: key, value: "second")
        XCTAssertEqual(KeychainHelper.load(key: key), "second")
    }
}
