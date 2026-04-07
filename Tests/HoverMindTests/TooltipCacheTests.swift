import XCTest
@testable import HoverMind

final class TooltipCacheTests: XCTestCase {

    func testSetAndGet() {
        let cache = TooltipCache()
        cache.set(key: "a", value: "hello")
        XCTAssertEqual(cache.get(key: "a"), "hello")
    }

    func testGetMissing() {
        let cache = TooltipCache()
        XCTAssertNil(cache.get(key: "missing"))
    }

    func testCount() {
        let cache = TooltipCache()
        XCTAssertEqual(cache.count, 0)
        cache.set(key: "a", value: "1")
        cache.set(key: "b", value: "2")
        XCTAssertEqual(cache.count, 2)
    }

    func testClear() {
        let cache = TooltipCache()
        cache.set(key: "a", value: "1")
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.get(key: "a"))
    }

    func testEviction() {
        let cache = TooltipCache(maxEntries: 2, ttl: 300)
        cache.set(key: "a", value: "1")
        cache.set(key: "b", value: "2")
        cache.set(key: "c", value: "3")
        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.get(key: "a"))
        XCTAssertEqual(cache.get(key: "c"), "3")
    }

    func testExpiry() {
        let cache = TooltipCache(maxEntries: 10, ttl: 0.01)
        cache.set(key: "a", value: "1")
        Thread.sleep(forTimeInterval: 0.02)
        XCTAssertNil(cache.get(key: "a"))
    }

    func testUpdateAtCapacityDoesNotEvict() {
        let cache = TooltipCache(maxEntries: 2, ttl: 300)
        cache.set(key: "a", value: "1")
        cache.set(key: "b", value: "2")
        // Update existing key at capacity — should NOT evict the other entry
        cache.set(key: "a", value: "updated")
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.get(key: "a"), "updated")
        XCTAssertEqual(cache.get(key: "b"), "2")
    }

    func testLRUEvictsLeastRecentlyAccessed() {
        let cache = TooltipCache(maxEntries: 2, ttl: 300)
        cache.set(key: "a", value: "1")
        cache.set(key: "b", value: "2")
        // Access "a" to make it more recent than "b"
        _ = cache.get(key: "a")
        // Add "c" — should evict "b" (least recently accessed), not "a"
        cache.set(key: "c", value: "3")
        XCTAssertEqual(cache.get(key: "a"), "1")
        XCTAssertNil(cache.get(key: "b"))
        XCTAssertEqual(cache.get(key: "c"), "3")
    }
}
