import Foundation

/// Thread-safe LRU cache with TTL for tooltip responses.
/// Access refreshes recency; eviction removes least recently used.
final class TooltipCache: @unchecked Sendable {
    private var entries: [String: Entry] = [:]
    private let maxEntries: Int
    private let ttl: TimeInterval
    private let lock = NSLock()

    private struct Entry {
        let value: String
        let created: Date
        var lastAccessed: Date
    }

    init(maxEntries: Int = 128, ttl: TimeInterval = 300) {
        self.maxEntries = maxEntries
        self.ttl = ttl
    }

    func get(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key] else { return nil }
        if Date().timeIntervalSince(entry.created) > ttl {
            entries.removeValue(forKey: key)
            return nil
        }
        // Refresh recency for LRU
        entry.lastAccessed = Date()
        entries[key] = entry
        return entry.value
    }

    func set(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        // Only evict if this is a NEW key and we're at capacity
        if entries[key] == nil && entries.count >= maxEntries {
            if let lru = entries.min(by: { $0.value.lastAccessed < $1.value.lastAccessed }) {
                entries.removeValue(forKey: lru.key)
            }
        }
        let now = Date()
        entries[key] = Entry(value: value, created: now, lastAccessed: now)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
