import Foundation

// MARK: - Zenflow Router Candidate

/// A workflow candidate in the Zenflow auto router configuration.
struct ZenflowRouterCandidate: Codable, Equatable, Identifiable {
    var id: String { workflowFileName }

    /// The workflow file name (e.g. "code-review.md").
    var workflowFileName: String

    /// Relative cost score (lower = cheaper).
    var cost: Double

    /// Relative quality score (higher = better).
    var quality: Double

    /// Capability description shown to the classifier.
    var card: String

    enum CodingKeys: String, CodingKey {
        case workflowFileName = "workflow_file_name"
        case cost
        case quality
        case card
    }
}

// MARK: - Zenflow Router Decision

/// A logged routing decision for observability.
struct ZenflowRouterDecision: Codable, Equatable {
    var timestamp: Date
    var taskHash: String
    var selectedWorkflow: String
    var confidence: Double
    var classifierUsed: String
    var reason: RouterDecisionReason

    enum CodingKeys: String, CodingKey {
        case timestamp
        case taskHash = "task_hash"
        case selectedWorkflow = "selected_workflow"
        case confidence
        case classifierUsed = "classifier_used"
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        taskHash = try container.decode(String.self, forKey: .taskHash)
        selectedWorkflow = try container.decode(String.self, forKey: .selectedWorkflow)
        confidence = try container.decode(Double.self, forKey: .confidence)
        classifierUsed = try container.decode(String.self, forKey: .classifierUsed)
        reason = try container.decodeIfPresent(RouterDecisionReason.self, forKey: .reason) ?? .unknown
    }

    init(timestamp: Date, taskHash: String, selectedWorkflow: String, confidence: Double, classifierUsed: String, reason: RouterDecisionReason = .unknown) {
        self.timestamp = timestamp
        self.taskHash = taskHash
        self.selectedWorkflow = selectedWorkflow
        self.confidence = confidence
        self.classifierUsed = classifierUsed
        self.reason = reason
    }
}

// MARK: - Zenflow Router Config

/// Top-level configuration for the Zenflow auto router, persisted per-project.
struct ZenflowRouterConfig: Codable, Equatable {
    var enabled: Bool
    var classifier: String
    var threshold: Double
    var defaultWorkflow: String
    var cache: Bool
    var candidates: [ZenflowRouterCandidate]

    enum CodingKeys: String, CodingKey {
        case enabled
        case classifier
        case threshold
        case defaultWorkflow = "default_workflow"
        case cache
        case candidates
    }
}

// MARK: - Cache Entry

/// A single entry in the routing decision cache.
struct ZenflowRouterCacheEntry: Codable, Equatable {
    var selectedWorkflow: String
    var confidence: Double
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case selectedWorkflow = "selected_workflow"
        case confidence
        case expiresAt = "expires_at"
    }
}
