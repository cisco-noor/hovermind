import Foundation

/// Simple file-based logger. Writes to ~/Library/Logs/HoverMind/hovermind.log.
enum Log {
    private static let logDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Logs/HoverMind"
    }()
    private static let logPath: String = {
        let dir = logDir
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: nil
        )
        return "\(dir)/hovermind.log"
    }()
    private static let lock = NSLock()

    static func info(_ message: String) {
        write("[INFO] \(message)")
    }

    static func error(_ message: String) {
        write("[ERROR] \(message)")
    }

    private static func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let ts = ISO8601DateFormatter().string(from: Date())
        let entry = "\(ts) \(line)\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }
}
