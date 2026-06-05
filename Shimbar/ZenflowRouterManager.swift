import Foundation
import Observation
import CryptoKit

// MARK: - ZenflowRouterManager

/// Manages the Zenflow auto router configuration and routing decisions.
/// Persists config to `~/.zenflow/router.json` and cache to `~/.zenflow/router-cache.json`.
@Observable
final class ZenflowRouterManager {
    static let shared = ZenflowRouterManager()

    private let fileManager = FileManager.default
    private let syncQueue = DispatchQueue(label: "com.shimbar.zenflow.router")

    var lastError: String?
    var config: ZenflowRouterConfig?
    private var cache: [String: ZenflowRouterCacheEntry] = [:]
    private var decisionLog: [ZenflowRouterDecision] = []
    private let maxDecisionLogSize = 50

    private var zenflowDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zenflow")
    }

    private var routerConfigURL: URL {
        zenflowDirectoryURL.appendingPathComponent("router.json")
    }

    private var routerCacheURL: URL {
        zenflowDirectoryURL.appendingPathComponent("router-cache.json")
    }

    private var decisionLogURL: URL {
        zenflowDirectoryURL.appendingPathComponent("router-decisions.json")
    }

    private init() {
        if !fileManager.fileExists(atPath: zenflowDirectoryURL.path) {
            try? fileManager.createDirectory(at: zenflowDirectoryURL, withIntermediateDirectories: true)
        }
        loadConfig()
        loadCache()
        loadDecisionLog()
    }

    // MARK: - Config Persistence

    func loadConfig() {
        syncQueue.sync {
            do {
                if fileManager.fileExists(atPath: routerConfigURL.path) {
                    let data = try Data(contentsOf: routerConfigURL)
                    let decoded = try JSONDecoder().decode(ZenflowRouterConfig.self, from: data)
                    config = decoded
                } else {
                    config = nil
                }
            } catch {
                lastError = "Failed to load router config: \(error.localizedDescription)"
                DebugLogger.log("ZenflowRouterManager: failed to load config: \(error)")
                config = nil
            }
        }
    }

    func saveConfig(_ config: ZenflowRouterConfig) throws {
        try validate(config)

        var thrownError: Error?
        syncQueue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(config)

                // Atomic write with .bak backup
                let bakURL = routerConfigURL.appendingPathExtension("bak")
                if fileManager.fileExists(atPath: routerConfigURL.path) {
                    try? fileManager.removeItem(at: bakURL)
                    try fileManager.copyItem(at: routerConfigURL, to: bakURL)
                }

                try data.write(to: routerConfigURL, options: .atomic)
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: routerConfigURL.path)

                self.config = config
                lastError = nil
            } catch {
                thrownError = error
                lastError = "Failed to save router config: \(error.localizedDescription)"
                DebugLogger.log("ZenflowRouterManager: failed to save config: \(error)")
            }
        }
        if let error = thrownError { throw error }
    }

    func deleteConfig() throws {
        var thrownError: Error?
        syncQueue.sync {
            do {
                if fileManager.fileExists(atPath: routerConfigURL.path) {
                    try fileManager.removeItem(at: routerConfigURL)
                }
                config = nil
                lastError = nil
            } catch {
                thrownError = error
                lastError = "Failed to delete router config: \(error.localizedDescription)"
                DebugLogger.log("ZenflowRouterManager: failed to delete config: \(error)")
            }
        }
        if let error = thrownError { throw error }
    }

    // MARK: - Validation

    func validate(_ config: ZenflowRouterConfig) throws {
        if config.enabled {
            if config.candidates.count < 2 {
                throw ValidationError.tooFewCandidates
            }
            if config.classifier.isEmpty {
                throw ValidationError.missingClassifier
            }
            if config.defaultWorkflow.isEmpty {
                throw ValidationError.missingDefaultWorkflow
            }
        }
    }

    enum ValidationError: LocalizedError {
        case tooFewCandidates
        case missingClassifier
        case missingDefaultWorkflow

        var errorDescription: String? {
            switch self {
            case .tooFewCandidates:
                return "Auto router requires at least 2 candidate workflows."
            case .missingClassifier:
                return "A classifier model must be selected."
            case .missingDefaultWorkflow:
                return "A default fallback workflow must be selected."
            }
        }
    }

    // MARK: - Cache

    private func loadCache() {
        syncQueue.sync {
            do {
                if fileManager.fileExists(atPath: routerCacheURL.path) {
                    let data = try Data(contentsOf: routerCacheURL)
                    let decoded = try JSONDecoder().decode([String: ZenflowRouterCacheEntry].self, from: data)
                    // Filter expired entries
                    let now = Date()
                    cache = decoded.filter { $0.value.expiresAt > now }
                } else {
                    cache = [:]
                }
            } catch {
                DebugLogger.log("ZenflowRouterManager: failed to load cache: \(error)")
                cache = [:]
            }
        }
    }

    private func saveCache() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cache)
        try data.write(to: routerCacheURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: routerCacheURL.path)
    }

    func lookupCache(taskHash: String) -> ZenflowRouterCacheEntry? {
        syncQueue.sync {
            guard let entry = cache[taskHash], entry.expiresAt > Date() else {
                return nil
            }
            return entry
        }
    }

    func setCache(taskHash: String, entry: ZenflowRouterCacheEntry) {
        syncQueue.sync {
            cache[taskHash] = entry
            try? saveCache()
        }
    }

    func clearCache() {
        syncQueue.sync {
            cache.removeAll()
            try? FileManager.default.removeItem(at: routerCacheURL)
        }
    }

    func clearDecisionLog() {
        syncQueue.sync {
            decisionLog.removeAll()
            try? FileManager.default.removeItem(at: decisionLogURL)
        }
    }

    // MARK: - Decision Log

    private func loadDecisionLog() {
        syncQueue.sync {
            do {
                if fileManager.fileExists(atPath: decisionLogURL.path) {
                    let data = try Data(contentsOf: decisionLogURL)
                    let decoded = try JSONDecoder().decode([ZenflowRouterDecision].self, from: data)
                    decisionLog = decoded
                } else {
                    decisionLog = []
                }
            } catch {
                DebugLogger.log("ZenflowRouterManager: failed to load decision log: \(error)")
                decisionLog = []
            }
        }
    }

    private func saveDecisionLog() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(decisionLog)
        try data.write(to: decisionLogURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: decisionLogURL.path)
    }

    func logDecision(_ decision: ZenflowRouterDecision) {
        syncQueue.sync {
            decisionLog.append(decision)
            if decisionLog.count > maxDecisionLogSize {
                decisionLog.removeFirst(decisionLog.count - maxDecisionLogSize)
            }
            try? saveDecisionLog()
        }
    }

    func recentDecisions(limit: Int = 10) -> [ZenflowRouterDecision] {
        syncQueue.sync {
            Array(decisionLog.suffix(limit).reversed())
        }
    }

    // MARK: - Routing

    /// Routes a task to the best workflow candidate.
    /// If the shim classifier is unavailable, falls back to the default workflow.
    func route(
        taskTitle: String,
        taskDescription: String,
        projectPath: String,
        shimClassifierAvailable: Bool
    ) -> String {
        guard let config = config, config.enabled else {
            let destination = config?.defaultWorkflow ?? ""
            RouterStatsManager.shared.recordEntry(RouterUsageEntry(
                timestamp: Date(),
                selectedDestination: destination,
                classifierUsed: "",
                confidence: 0,
                taskHash: Self.hashTask(taskTitle: taskTitle, taskDescription: taskDescription, projectPath: projectPath),
                cacheHit: false,
                reason: .disabled
            ))
            return destination
        }

        let taskHash = Self.hashTask(taskTitle: taskTitle, taskDescription: taskDescription, projectPath: projectPath)

        if config.cache, let cached = lookupCache(taskHash: taskHash) {
            DebugLogger.log("ZenflowRouterManager: cache hit for hash \(taskHash) -> \(cached.selectedWorkflow)")
            RouterStatsManager.shared.recordEntry(RouterUsageEntry(
                timestamp: Date(),
                selectedDestination: cached.selectedWorkflow,
                classifierUsed: "",
                confidence: cached.confidence,
                taskHash: taskHash,
                cacheHit: true,
                reason: .cacheHit
            ))
            return cached.selectedWorkflow
        }

        if !shimClassifierAvailable {
            DebugLogger.log("ZenflowRouterManager: classifier unavailable, using default \(config.defaultWorkflow)")
            RouterStatsManager.shared.recordEntry(RouterUsageEntry(
                timestamp: Date(),
                selectedDestination: config.defaultWorkflow,
                classifierUsed: "",
                confidence: 0,
                taskHash: taskHash,
                cacheHit: false,
                reason: .shimOffline
            ))
            return config.defaultWorkflow
        }

        return config.defaultWorkflow
    }

    /// Full async routing flow: checks cache, calls classifier if needed, applies result.
    /// This is the primary entry point for production code. The synchronous `route()` is
    /// kept for backward compatibility and tests.
    func routeFully(
        taskTitle: String,
        taskDescription: String,
        projectPath: String,
        classifierAvailable: Bool,
        callClassifier: (String, String) async -> String?
    ) async -> String {
        guard let config = config, config.enabled else {
            return route(
                taskTitle: taskTitle,
                taskDescription: taskDescription,
                projectPath: projectPath,
                shimClassifierAvailable: classifierAvailable
            )
        }

        let taskHash = Self.hashTask(taskTitle: taskTitle, taskDescription: taskDescription, projectPath: projectPath)

        if config.cache, let cached = lookupCache(taskHash: taskHash) {
            DebugLogger.log("ZenflowRouterManager: cache hit for hash \(taskHash) -> \(cached.selectedWorkflow)")
            RouterStatsManager.shared.recordEntry(RouterUsageEntry(
                timestamp: Date(),
                selectedDestination: cached.selectedWorkflow,
                classifierUsed: "",
                confidence: cached.confidence,
                taskHash: taskHash,
                cacheHit: true,
                reason: .cacheHit
            ))
            return cached.selectedWorkflow
        }

        if !classifierAvailable {
            DebugLogger.log("ZenflowRouterManager: classifier unavailable, using default \(config.defaultWorkflow)")
            RouterStatsManager.shared.recordEntry(RouterUsageEntry(
                timestamp: Date(),
                selectedDestination: config.defaultWorkflow,
                classifierUsed: "",
                confidence: 0,
                taskHash: taskHash,
                cacheHit: false,
                reason: .shimOffline
            ))
            return config.defaultWorkflow
        }

        let prompt = buildClassifierPrompt(taskTitle: taskTitle, taskDescription: taskDescription, candidates: config.candidates)

        guard let classifierOutput = await callClassifier(config.classifier, prompt) else {
            DebugLogger.log("ZenflowRouterManager: classifier call failed, using default")
            RouterStatsManager.shared.recordEntry(RouterUsageEntry(
                timestamp: Date(),
                selectedDestination: config.defaultWorkflow,
                classifierUsed: config.classifier,
                confidence: 0,
                taskHash: taskHash,
                cacheHit: false,
                reason: .classifierMissing
            ))
            return config.defaultWorkflow
        }

        return applyClassifierResult(
            classifierOutput: classifierOutput,
            taskTitle: taskTitle,
            taskDescription: taskDescription,
            projectPath: projectPath,
            classifierModel: config.classifier
        )
    }

    private func buildClassifierPrompt(taskTitle: String, taskDescription: String, candidates: [ZenflowRouterCandidate]) -> String {
        var cards = ""
        for candidate in candidates {
            cards += "- \(candidate.workflowFileName): \(candidate.card)\n"
        }
        return """
        You are a task router. Given a task, select the best workflow from the candidates below.

        Candidates:
        \(cards)

        Task title: \(taskTitle)
        Task description: \(taskDescription)

        Respond with ONLY a JSON object: {"workflow": "<file_name>", "confidence": <0.0-1.0>}
        """
    }

    /// Applies a classifier result to determine the selected workflow.
    func applyClassifierResult(
        classifierOutput: String,
        taskTitle: String,
        taskDescription: String,
        projectPath: String,
        classifierModel: String
    ) -> String {
        guard let config = config, config.enabled else {
            let destination = config?.defaultWorkflow ?? ""
            RouterStatsManager.shared.recordEntry(RouterUsageEntry(
                timestamp: Date(),
                selectedDestination: destination,
                classifierUsed: classifierModel,
                confidence: 0,
                taskHash: Self.hashTask(taskTitle: taskTitle, taskDescription: taskDescription, projectPath: projectPath),
                cacheHit: false,
                reason: .disabled
            ))
            return destination
        }

        let normalized = classifierOutput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let (parsedWorkflow, parsedConfidence) = Self.parseClassifierOutput(normalized)

        var selected = config.candidates.first { candidate in
            candidate.workflowFileName.lowercased() == parsedWorkflow ||
            candidate.workflowFileName.replacingOccurrences(of: "-", with: "").lowercased() == parsedWorkflow
        }

        var reason: RouterDecisionReason = .classified
        let finalConfidence = parsedConfidence

        if selected == nil || finalConfidence < config.threshold {
            if selected == nil {
                selected = config.candidates.first { $0.workflowFileName == config.defaultWorkflow }
            }
            reason = .lowConfidence
        }

        let selectedWorkflow = selected?.workflowFileName ?? config.defaultWorkflow

        let taskHash = Self.hashTask(taskTitle: taskTitle, taskDescription: taskDescription, projectPath: projectPath)

        let expiresAt = Date().addingTimeInterval(24 * 60 * 60)
        setCache(taskHash: taskHash, entry: ZenflowRouterCacheEntry(
            selectedWorkflow: selectedWorkflow,
            confidence: finalConfidence,
            expiresAt: expiresAt
        ))

        logDecision(ZenflowRouterDecision(
            timestamp: Date(),
            taskHash: taskHash,
            selectedWorkflow: selectedWorkflow,
            confidence: finalConfidence,
            classifierUsed: classifierModel,
            reason: reason
        ))

        RouterStatsManager.shared.recordEntry(RouterUsageEntry(
            timestamp: Date(),
            selectedDestination: selectedWorkflow,
            classifierUsed: classifierModel,
            confidence: finalConfidence,
            taskHash: taskHash,
            cacheHit: false,
            reason: reason
        ))

        return selectedWorkflow
    }

    /// Parses classifier output to extract workflow name and confidence.
    /// Supports JSON `{"workflow": "...", "confidence": 0.9}` or plain text.
    private static func parseClassifierOutput(_ output: String) -> (workflow: String, confidence: Double) {
        let cleaned = output
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let workflow = (json["workflow"] as? String ?? cleaned).lowercased()
            let confidence = json["confidence"] as? Double ?? 0.75
            return (workflow, confidence)
        }

        return (cleaned, 0.75)
    }

    // MARK: - Helpers

    static func hashTask(taskTitle: String, taskDescription: String, projectPath: String) -> String {
        let input = "\(projectPath)|\(taskTitle)|\(taskDescription)"
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
