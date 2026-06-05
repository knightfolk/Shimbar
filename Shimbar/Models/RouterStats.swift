import Foundation
import Observation

// MARK: - RouterUsageEntry

struct RouterUsageEntry: Codable, Equatable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(selectedDestination)-\(taskHash.prefix(8))" }

    var timestamp: Date
    var selectedDestination: String
    var classifierUsed: String
    var confidence: Double
    var taskHash: String
    var cacheHit: Bool
    var reason: RouterDecisionReason

    enum CodingKeys: String, CodingKey {
        case timestamp
        case selectedDestination = "selected_destination"
        case classifierUsed = "classifier_used"
        case confidence
        case taskHash = "task_hash"
        case cacheHit = "cache_hit"
        case reason
    }
}

// MARK: - RouterDecisionReason

enum RouterDecisionReason: String, Codable, Equatable {
    case classified
    case lowConfidence = "low_confidence"
    case disabled
    case shimOffline = "shim_offline"
    case classifierMissing = "classifier_missing"
    case parseError = "parse_error"
    case cacheHit = "cache_hit"
    case unknown
}

// MARK: - RouterStatsSummary

struct RouterStatsSummary: Equatable {
    var totalCalls: Int
    var cacheHitRate: Double
    var averageConfidence: Double
    var destinationCounts: [String: Int]

    var mostUsedDestination: String? {
        destinationCounts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - RouterStatsManager

@Observable
final class RouterStatsManager {
    static let shared = RouterStatsManager()

    private let fileManager = FileManager.default
    private let syncQueue = DispatchQueue(label: "com.shimbar.router-stats")

    private var entries: [RouterUsageEntry] = []
    private let maxEntries = 1000

    var lastError: String?

    private var zenflowDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zenflow")
    }

    private var statsURL: URL {
        zenflowDirectoryURL.appendingPathComponent("router-stats.json")
    }

    private init() {
        if !fileManager.fileExists(atPath: zenflowDirectoryURL.path) {
            try? fileManager.createDirectory(at: zenflowDirectoryURL, withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: - Persistence

    private func load() {
        syncQueue.sync {
            do {
                if fileManager.fileExists(atPath: statsURL.path) {
                    let data = try Data(contentsOf: statsURL)
                    entries = try JSONDecoder().decode([RouterUsageEntry].self, from: data)
                } else {
                    entries = []
                }
            } catch {
                DebugLogger.log("RouterStatsManager: failed to load: \(error)")
                entries = []
            }
        }
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: statsURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statsURL.path)
    }

    // MARK: - Recording

    func recordEntry(_ entry: RouterUsageEntry) {
        syncQueue.sync {
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
            do {
                try save()
                lastError = nil
            } catch {
                lastError = "Failed to save router stats: \(error.localizedDescription)"
                DebugLogger.log("RouterStatsManager: failed to save: \(error)")
            }
        }
    }

    // MARK: - Queries

    func getRecentEntries(limit: Int = 20) -> [RouterUsageEntry] {
        syncQueue.sync {
            Array(entries.suffix(limit).reversed())
        }
    }

    func getSummary() -> RouterStatsSummary {
        syncQueue.sync {
            let total = entries.count
            guard total > 0 else {
                return RouterStatsSummary(totalCalls: 0, cacheHitRate: 0, averageConfidence: 0, destinationCounts: [:])
            }

            let cacheHits = entries.filter(\.cacheHit).count
            let cacheRate = Double(cacheHits) / Double(total)

            let classifiedEntries = entries.filter { $0.reason == .classified || $0.reason == .lowConfidence }
            let avgConfidence = classifiedEntries.isEmpty ? 0 : classifiedEntries.reduce(0) { $0 + $1.confidence } / Double(classifiedEntries.count)

            var counts: [String: Int] = [:]
            for entry in entries {
                counts[entry.selectedDestination, default: 0] += 1
            }

            return RouterStatsSummary(
                totalCalls: total,
                cacheHitRate: cacheRate,
                averageConfidence: avgConfidence,
                destinationCounts: counts
            )
        }
    }

    func getEntriesSince(_ date: Date) -> [RouterUsageEntry] {
        syncQueue.sync {
            entries.filter { $0.timestamp >= date }
        }
    }

    func allEntries() -> [RouterUsageEntry] {
        syncQueue.sync {
            entries
        }
    }

    // MARK: - Management

    func clearStats() {
        syncQueue.sync {
            entries.removeAll()
            try? fileManager.removeItem(at: statsURL)
        }
    }
}

// MARK: - ShimRequestStat

struct ShimRequestStat: Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(model)" }
    var timestamp: Date
    var model: String
    var endpoint: String
    var stream: Bool
    var toolCount: Int
}

// MARK: - ShimModelStatsSummary

struct ShimModelStatsSummary: Equatable {
    var totalRequests: Int
    var modelCounts: [String: Int]
    var autoRouterRequests: Int
    var directModelRequests: Int
    var requestsOverTime: [String: Int]

    var mostUsedModel: String? {
        modelCounts.max(by: { $0.value < $1.value })?.key
    }

    var autoRouterPercentage: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(autoRouterRequests) / Double(totalRequests)
    }
}

// MARK: - ShimLogStatsCollector

@Observable
final class ShimLogStatsCollector {
    static let shared = ShimLogStatsCollector()

    private let fileManager = FileManager.default
    private let syncQueue = DispatchQueue(label: "com.shimbar.shim-log-stats")

    private var stats: [ShimRequestStat] = []
    private var lastParsedOffset: UInt64 = 0
    private var lastParsedFileSize: UInt64 = 0

    var lastError: String?

    private var codexShimDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex-shim")
    }

    private var logURL: URL {
        codexShimDirectoryURL.appendingPathComponent("shim.log")
    }

    private var stateURL: URL {
        codexShimDirectoryURL.appendingPathComponent(".shim-stats-state.json")
    }

    private init() {
        loadState()
        parseLog()
    }

    private struct ParseState: Codable {
        var lastParsedOffset: UInt64
        var lastParsedFileSize: UInt64
    }

    private func loadState() {
        guard fileManager.fileExists(atPath: stateURL.path) else { return }
        do {
            let data = try Data(contentsOf: stateURL)
            let state = try JSONDecoder().decode(ParseState.self, from: data)
            lastParsedOffset = state.lastParsedOffset
            lastParsedFileSize = state.lastParsedFileSize
        } catch {
            lastParsedOffset = 0
            lastParsedFileSize = 0
        }
    }

    private func saveState() {
        let state = ParseState(lastParsedOffset: lastParsedOffset, lastParsedFileSize: lastParsedFileSize)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    func parseLog() {
        syncQueue.sync {
            guard fileManager.fileExists(atPath: logURL.path) else { return }

            do {
                let handle = try FileHandle(forReadingFrom: logURL)
                let fileSize = try handle.seekToEnd()

                if fileSize < lastParsedFileSize {
                    lastParsedOffset = 0
                    stats.removeAll()
                }

                if lastParsedOffset >= fileSize {
                    try? handle.close()
                    return
                }

                try handle.seek(toOffset: lastParsedOffset)
                let data = try handle.readToEnd() ?? Data()
                try? handle.close()

                let content = String(data: data, encoding: .utf8) ?? ""
                let newStats = Self.parseRequestLines(content)

                if !newStats.isEmpty {
                    stats.append(contentsOf: newStats)
                    let maxStats = 5000
                    if stats.count > maxStats {
                        stats.removeFirst(stats.count - maxStats)
                    }
                }

                lastParsedOffset = fileSize
                lastParsedFileSize = fileSize
                saveState()
                lastError = nil
            } catch {
                lastError = "Failed to parse shim.log: \(error.localizedDescription)"
            }
        }
    }

    private static let reqPattern = try! NSRegularExpression(
        pattern: #"^\[req\]\s+(\S+)\s+model='([^']+)'.*stream=(\w+)"#,
        options: []
    )

    private static func parseRequestLines(_ content: String) -> [ShimRequestStat] {
        var results: [ShimRequestStat] = []
        let now = Date()
        let totalCount = content.components(separatedBy: "[req]").count - 1
        let intervalPerLine: Double = totalCount > 1 ? 1.0 / Double(totalCount) : 0

        var index = 0
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[req]") else { continue }

            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = reqPattern.firstMatch(in: trimmed, range: range) else { continue }

            let endpoint = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
            let model = String(trimmed[Range(match.range(at: 2), in: trimmed)!])
            let streamStr = String(trimmed[Range(match.range(at: 3), in: trimmed)!])

            let toolCount: Int
            if let toolsMatch = trimmed.range(of: #"tools=(\d+)"#, options: .regularExpression) {
                let toolsStr = String(trimmed[toolsMatch])
                let numStr = toolsStr.replacingOccurrences(of: "tools=", with: "")
                toolCount = Int(numStr) ?? 0
            } else {
                toolCount = 0
            }

            let estimatedTimestamp = now.addingTimeInterval(-Double(totalCount - index) * intervalPerLine)

            results.append(ShimRequestStat(
                timestamp: estimatedTimestamp,
                model: model,
                endpoint: endpoint,
                stream: streamStr == "True",
                toolCount: toolCount
            ))
            index += 1
        }
        return results
    }

    func getSummary() -> ShimModelStatsSummary {
        syncQueue.sync {
            let total = stats.count
            guard total > 0 else {
                return ShimModelStatsSummary(
                    totalRequests: 0,
                    modelCounts: [:],
                    autoRouterRequests: 0,
                    directModelRequests: 0,
                    requestsOverTime: [:]
                )
            }

            var counts: [String: Int] = [:]
            var autoRouterCount = 0
            var directCount = 0

            for stat in stats {
                counts[stat.model, default: 0] += 1
                if stat.model.hasPrefix("codex-auto") {
                    autoRouterCount += 1
                } else {
                    directCount += 1
                }
            }

            var hourlyCounts: [String: Int] = [:]
            let hourFormatter = DateFormatter()
            hourFormatter.dateFormat = "yyyy-MM-dd HH:00"
            for stat in stats {
                let key = hourFormatter.string(from: stat.timestamp)
                hourlyCounts[key, default: 0] += 1
            }

            return ShimModelStatsSummary(
                totalRequests: total,
                modelCounts: counts,
                autoRouterRequests: autoRouterCount,
                directModelRequests: directCount,
                requestsOverTime: hourlyCounts
            )
        }
    }

    func getRecentStats(limit: Int = 50) -> [ShimRequestStat] {
        syncQueue.sync {
            Array(stats.suffix(limit).reversed())
        }
    }

    func getStatsForModel(_ model: String) -> [ShimRequestStat] {
        syncQueue.sync {
            stats.filter { $0.model == model }
        }
    }

    func allStats() -> [ShimRequestStat] {
        syncQueue.sync { stats }
    }

    func clearStats() {
        syncQueue.sync {
            stats.removeAll()
            lastParsedOffset = 0
            lastParsedFileSize = 0
            try? fileManager.removeItem(at: stateURL)
        }
    }
}
