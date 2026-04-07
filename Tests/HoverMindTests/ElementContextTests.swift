import XCTest
@testable import HoverMind

final class ElementContextTests: XCTestCase {

    func testCacheKeyStable() {
        let ctx = ElementContext(
            appName: "Chrome", bundleId: "com.google.Chrome", role: "AXButton",
            roleDescription: "button", title: "Submit", value: nil,
            label: "Submit form", help: nil, pid: 123, browserURL: "https://example.com",
            selectedText: nil, parentChain: []
        )
        XCTAssertEqual(ctx.cacheKey, ctx.cacheKey)
    }

    func testCacheKeyDiffers() {
        let a = makeContext(title: "Submit")
        let b = makeContext(title: "Cancel")
        XCTAssertNotEqual(a.cacheKey, b.cacheKey)
    }

    func testCacheKeyURLAware() {
        let a = makeContext(browserURL: "https://github.com")
        let b = makeContext(browserURL: "https://gitlab.com")
        XCTAssertNotEqual(a.cacheKey, b.cacheKey)
    }

    func testCacheKeyParentChain() {
        let a = makeContext(parentChain: [.init(role: "AXToolbar", title: nil)])
        let b = makeContext(parentChain: [.init(role: "AXWebArea", title: nil)])
        XCTAssertNotEqual(a.cacheKey, b.cacheKey)
    }

    func testPromptDescriptionIncludesFields() {
        let ctx = ElementContext(
            appName: "Safari", bundleId: "com.apple.Safari", role: "AXButton",
            roleDescription: "button", title: "Go", value: "active",
            label: "Navigate", help: "Click to go", pid: 1,
            browserURL: "https://example.com", selectedText: "hello",
            parentChain: [.init(role: "AXToolbar", title: "Main")]
        )
        let desc = ctx.promptDescription
        XCTAssert(desc.contains("Safari"))
        XCTAssert(desc.contains("AXButton"))
        XCTAssert(desc.contains("https://example.com"))
        XCTAssert(desc.contains("hello"))
    }

    func testCacheKeySelectedTextAware() {
        let a = makeContext(selectedText: "hello world")
        let b = makeContext(selectedText: "goodbye world")
        let c = makeContext(selectedText: nil)
        XCTAssertNotEqual(a.cacheKey, b.cacheKey)
        XCTAssertNotEqual(a.cacheKey, c.cacheKey)
    }

    private func makeContext(
        title: String? = "Test",
        browserURL: String? = nil,
        selectedText: String? = nil,
        parentChain: [ElementContext.ParentElement] = []
    ) -> ElementContext {
        ElementContext(
            appName: "Chrome", bundleId: "com.google.Chrome", role: "AXButton",
            roleDescription: nil, title: title, value: nil,
            label: nil, help: nil, pid: 1, browserURL: browserURL,
            selectedText: selectedText, parentChain: parentChain
        )
    }
}
