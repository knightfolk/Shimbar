import Foundation

enum DebugLogger {
    static let maxLogSize: UInt64 = 1_048_576

    static func log(_ message: String) {
        #if DEBUG
        let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("shimbar_debug.log")

        rotateIfNeeded(logURL)

        let entry = "\(Date()): \(message)\n"
        guard let data = entry.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: logURL)
        }
        #endif
    }

    static func rotateIfNeeded(_ url: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else { return }
        try? fm.removeItem(at: url)
    }
}
