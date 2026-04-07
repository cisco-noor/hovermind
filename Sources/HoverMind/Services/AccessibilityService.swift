import ApplicationServices
import AppKit

/// Inspects UI elements at screen coordinates using the macOS Accessibility API (AXUIElement).
final class AccessibilityService {

    private let ownPid = ProcessInfo.processInfo.processIdentifier

    /// Checks Accessibility permission without prompting.
    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        )
    }

    /// Opens System Settings to the Accessibility pane so the user can grant access.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns the element context at the given screen point.
    /// `screenPoint` uses AppKit coordinates (origin at bottom-left of primary display).
    func elementAt(screenPoint: NSPoint) -> ElementContext? {
        // CG coordinates use top-left origin of primary display.
        // Primary display is always NSScreen.screens[0].
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let cgPoint = CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)

        let systemWide = AXUIElementCreateSystemWide()
        var rawElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide, Float(cgPoint.x), Float(cgPoint.y), &rawElement
        )
        guard result == .success, let element = rawElement else { return nil }

        // Identify the owning application
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        // Ignore our own app's elements (tooltip, menu bar, settings)
        guard pid != ownPid else { return nil }

        let app = NSRunningApplication(processIdentifier: pid)

        let bundleId = app?.bundleIdentifier

        return ElementContext(
            appName: app?.localizedName ?? "Unknown",
            bundleId: bundleId,
            role: attribute(element, kAXRoleAttribute) ?? "unknown",
            roleDescription: attribute(element, kAXRoleDescriptionAttribute),
            title: attribute(element, kAXTitleAttribute),
            value: attribute(element, kAXValueAttribute),
            label: attribute(element, kAXDescriptionAttribute),
            help: attribute(element, kAXHelpAttribute),
            pid: pid,
            browserURL: browserURL(pid: pid, bundleId: bundleId),
            selectedText: selectedText(element, pid: pid),
            parentChain: parentChain(of: element, maxDepth: 3)
        )
    }

    // MARK: - Private

    private func attribute(_ element: AXUIElement, _ key: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
            return nil
        }
        if let str = value as? String, !str.isEmpty { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    /// Reads any selected text from the element or the app's focused element.
    private func selectedText(_ element: AXUIElement, pid: pid_t) -> String? {
        // Try the element under cursor first
        if let text = attribute(element, kAXSelectedTextAttribute) { return text }

        // Fall back to the app's focused UI element (handles text fields, web areas)
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success,
              let ref = focusedRef,
              CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        // Safe: CFGetTypeID check above guarantees this is an AXUIElement
        let focused = ref as! AXUIElement
        return attribute(focused, kAXSelectedTextAttribute)
    }

    /// Extracts the current page URL from a browser window via Accessibility.
    /// Chrome/Edge/Arc expose the URL as the AXDocument attribute on the focused window.
    private func browserURL(pid: pid_t, bundleId: String?) -> String? {
        let browsers = [
            "com.google.Chrome", "com.google.Chrome.canary",
            "com.apple.Safari", "company.thebrowser.Browser",
            "org.mozilla.firefox", "com.microsoft.edgemac",
        ]
        guard let bid = bundleId, browsers.contains(bid) else { return nil }

        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused window
        var windowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success,
              let wRef = windowRef,
              CFGetTypeID(wRef) == AXUIElementGetTypeID()
        else { return nil }
        // Safe: CFGetTypeID check above guarantees this is an AXUIElement
        let window = wRef as! AXUIElement

        // Chrome, Edge, Arc: AXDocument attribute on the window
        if let url = attribute(window, "AXDocument") { return url }

        // Safari: look for AXURL on child web area
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(
            window, kAXChildrenAttribute as CFString, &children
        ) == .success, let childArray = children as? [AXUIElement] else { return nil }

        for child in childArray {
            if let role = attribute(child, kAXRoleAttribute), role == "AXWebArea" {
                if let url = attribute(child, "AXURL") { return url }
                if let url = attribute(child, "AXDocument") { return url }
            }
        }

        return nil
    }

    private func parentChain(of element: AXUIElement, maxDepth: Int) -> [ElementContext.ParentElement] {
        var chain: [ElementContext.ParentElement] = []
        var current = element

        for _ in 0..<maxDepth {
            var parentRef: AnyObject?
            guard AXUIElementCopyAttributeValue(
                current, kAXParentAttribute as CFString, &parentRef
            ) == .success,
                  let pRef = parentRef,
                  CFGetTypeID(pRef) == AXUIElementGetTypeID()
            else { break }
            // Safe: CFGetTypeID check above guarantees this is an AXUIElement
            let parent = pRef as! AXUIElement

            let role = attribute(parent, kAXRoleAttribute) ?? "unknown"
            let title = attribute(parent, kAXTitleAttribute)
            chain.append(.init(role: role, title: title))
            current = parent
        }
        return chain
    }
}
