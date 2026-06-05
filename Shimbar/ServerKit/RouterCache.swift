import Foundation

enum RouterCache {
    static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".zenflow/router-cache.json")

    static func reset() {
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheURL.path) {
            try? fm.removeItem(at: cacheURL)
        }
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: cacheURL.path)
    }
}
