import Foundation

/// Accessibility context of a UI element under the cursor.
struct ElementContext: Sendable {
    let appName: String
    let bundleId: String?
    let role: String
    let roleDescription: String?
    let title: String?
    let value: String?
    let label: String?
    let help: String?
    let pid: pid_t
    let browserURL: String?
    let selectedText: String?
    let parentChain: [ParentElement]

    struct ParentElement: Sendable {
        let role: String
        let title: String?
    }

    /// Cache key: computed once at init, not on every access.
    let cacheKey: String

    init(appName: String, bundleId: String?, role: String, roleDescription: String?,
         title: String?, value: String?, label: String?, help: String?,
         pid: pid_t, browserURL: String?, selectedText: String?, parentChain: [ParentElement]) {
        self.appName = appName; self.bundleId = bundleId; self.role = role
        self.roleDescription = roleDescription; self.title = title; self.value = value
        self.label = label; self.help = help; self.pid = pid
        self.browserURL = browserURL; self.selectedText = selectedText
        self.parentChain = parentChain
        let parentSig = parentChain.map { $0.title ?? $0.role }.joined(separator: ">")
        self.cacheKey = "\(bundleId ?? appName)|\(role)|\(title ?? "")|\(label ?? "")|\(value ?? "")|\(roleDescription ?? "")|\(help ?? "")|\(browserURL ?? "")|\(selectedText ?? "")|\(parentSig)"
    }

    /// Formats element metadata for the AI prompt.
    var promptDescription: String {
        var lines: [String] = []
        lines.append("App: \(appName)")
        if let bundleId { lines.append("Bundle ID: \(bundleId)") }
        lines.append("Element role: \(role)")
        if let roleDescription { lines.append("Role description: \(roleDescription)") }
        if let title { lines.append("Title: \(title)") }
        if let value { lines.append("Current value: \(value)") }
        if let label { lines.append("Accessibility label: \(label)") }
        if let help { lines.append("Help text: \(help)") }
        if let browserURL { lines.append("Browser URL: \(browserURL)") }
        if let selectedText { lines.append("Selected text: \(selectedText)") }
        if !parentChain.isEmpty {
            let chain = parentChain.map { p in
                p.title.map { "\(p.role): \($0)" } ?? p.role
            }.joined(separator: " > ")
            lines.append("Parent chain: \(chain)")
        }
        return lines.joined(separator: "\n")
    }
}
