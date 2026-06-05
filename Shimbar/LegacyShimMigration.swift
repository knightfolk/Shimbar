import Foundation

enum LegacyShimMigration {

    private static let didMigrateKey = "shimbar.legacyShimPidMigrated"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didMigrateKey) else { return }

        let pidURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-shim/shim.pid")

        guard let pidString = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0
        else {
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        let sigSuccess = kill(pid, 0) == 0
        guard sigSuccess else {
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        let procPath = procPath(for: pid)
        if procPath.contains("python") || procPath.contains("codex-shim") {
            kill(pid, SIGTERM)

            let logURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex-shim/shim.log")
            let banner = "[\(Date().iso8601String)] [SHIMBAR] Detected legacy codex-shim (PID \(pid)); stopped it. Shimbar is now serving the same port natively.\n"
            if let data = banner.data(using: .utf8) {
                let fm = FileManager.default
                if fm.fileExists(atPath: logURL.path) {
                    let handle = try? FileHandle(forWritingTo: logURL)
                    try? handle?.seekToEnd()
                    try? handle?.write(contentsOf: data)
                    try? handle?.close()
                } else {
                    try? data.write(to: logURL, options: .atomic)
                }
            }
        }

        defaults.set(true, forKey: didMigrateKey)
    }

    private static func procPath(for pid: Int32) -> String {
        var path = [CChar](repeating: 0, count: 1024)
        let count = proc_pidpath(pid, &path, UInt32(path.count))
        guard count > 0 else { return "" }
        return String(cString: path)
    }
}

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
