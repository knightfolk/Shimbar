import XCTest
@testable import Shimbar

final class ZenflowRouterConfigTests: XCTestCase {

    // MARK: - Encoding / Decoding

    func testRoundTripEncoding() throws {
        let original = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.75,
            defaultWorkflow: "code-review.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(
                    workflowFileName: "code-review.md",
                    cost: 1.0,
                    quality: 3.0,
                    card: "Peer code review workflow"
                ),
                ZenflowRouterCandidate(
                    workflowFileName: "security-audit.md",
                    cost: 2.5,
                    quality: 5.0,
                    card: "Security vulnerability audit"
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ZenflowRouterConfig.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {
            "enabled": true,
            "classifier": "claude-sonnet-4",
            "threshold": 0.8,
            "default_workflow": "refactor-plan.md",
            "cache": false,
            "candidates": [
                {
                    "workflow_file_name": "refactor-plan.md",
                    "cost": 1.5,
                    "quality": 4.0,
                    "card": "Refactoring plan workflow"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(ZenflowRouterConfig.self, from: data)

        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.classifier, "claude-sonnet-4")
        XCTAssertEqual(config.threshold, 0.8, accuracy: 0.001)
        XCTAssertEqual(config.defaultWorkflow, "refactor-plan.md")
        XCTAssertFalse(config.cache)
        XCTAssertEqual(config.candidates.count, 1)
        XCTAssertEqual(config.candidates.first?.workflowFileName, "refactor-plan.md")
        XCTAssertEqual(config.candidates.first?.cost ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(config.candidates.first?.quality ?? 0, 4.0, accuracy: 0.001)
    }

    func testCandidateIdentifiable() {
        let candidate = ZenflowRouterCandidate(
            workflowFileName: "test.md",
            cost: 1.0,
            quality: 2.0,
            card: "Test"
        )
        XCTAssertEqual(candidate.id, "test.md")
    }

    // MARK: - Cache Entry

    func testCacheEntryRoundTrip() throws {
        let original = ZenflowRouterCacheEntry(
            selectedWorkflow: "code-review.md",
            confidence: 0.85,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ZenflowRouterCacheEntry.self, from: data)

        XCTAssertEqual(decoded.selectedWorkflow, original.selectedWorkflow)
        XCTAssertEqual(decoded.confidence, original.confidence, accuracy: 0.001)
        XCTAssertEqual(decoded.expiresAt.timeIntervalSince1970, original.expiresAt.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Decision Log

    func testDecisionRoundTrip() throws {
        let original = ZenflowRouterDecision(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            taskHash: "abc123",
            selectedWorkflow: "security-audit.md",
            confidence: 0.92,
            classifierUsed: "gpt-4o"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ZenflowRouterDecision.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
