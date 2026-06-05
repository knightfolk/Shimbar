import XCTest
@testable import Shimbar

final class ZenflowRouterManagerTests: XCTestCase {

    private var manager: ZenflowRouterManager!

    override func setUp() {
        super.setUp()
        manager = ZenflowRouterManager.shared
        // Clean up any existing test config
        try? manager.deleteConfig()
        manager.clearCache()
        manager.clearDecisionLog()
    }

    override func tearDown() {
        try? manager.deleteConfig()
        manager.clearCache()
        manager.clearDecisionLog()
        super.tearDown()
    }

    // MARK: - Validation

    func testValidationTooFewCandidates() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "test.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "test.md", cost: 1.0, quality: 2.0, card: "Test")
            ]
        )

        XCTAssertThrowsError(try manager.validate(config)) { error in
            guard let validationError = error as? ZenflowRouterManager.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            XCTAssertEqual(validationError, .tooFewCandidates)
        }
    }

    func testValidationMissingClassifier() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "",
            threshold: 0.7,
            defaultWorkflow: "test.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )

        XCTAssertThrowsError(try manager.validate(config)) { error in
            guard let validationError = error as? ZenflowRouterManager.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            XCTAssertEqual(validationError, .missingClassifier)
        }
    }

    func testValidationMissingDefaultWorkflow() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )

        XCTAssertThrowsError(try manager.validate(config)) { error in
            guard let validationError = error as? ZenflowRouterManager.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            XCTAssertEqual(validationError, .missingDefaultWorkflow)
        }
    }

    func testValidationPassesWithValidConfig() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )

        XCTAssertNoThrow(try manager.validate(config))
    }

    func testValidationDisabledConfigIgnoresCandidates() {
        let config = ZenflowRouterConfig(
            enabled: false,
            classifier: "",
            threshold: 0.7,
            defaultWorkflow: "",
            cache: true,
            candidates: []
        )

        XCTAssertNoThrow(try manager.validate(config))
    }

    // MARK: - Save / Load / Delete

    func testSaveAndLoadConfig() throws {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "claude-sonnet-4",
            threshold: 0.85,
            defaultWorkflow: "code-review.md",
            cache: false,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "code-review.md", cost: 1.0, quality: 3.0, card: "Code review"),
                ZenflowRouterCandidate(workflowFileName: "security-audit.md", cost: 2.5, quality: 5.0, card: "Security audit")
            ]
        )

        try manager.saveConfig(config)
        manager.loadConfig()

        XCTAssertEqual(manager.config, config)
        XCTAssertNil(manager.lastError)
    }

    func testDeleteConfig() throws {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "test.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )

        try manager.saveConfig(config)
        XCTAssertNotNil(manager.config)

        try manager.deleteConfig()
        XCTAssertNil(manager.config)
    }

    // MARK: - Cache

    func testCacheSetAndLookup() {
        let entry = ZenflowRouterCacheEntry(
            selectedWorkflow: "test-workflow.md",
            confidence: 0.9,
            expiresAt: Date().addingTimeInterval(3600)
        )

        manager.setCache(taskHash: "abc123", entry: entry)
        let lookedUp = manager.lookupCache(taskHash: "abc123")

        XCTAssertNotNil(lookedUp)
        XCTAssertEqual(lookedUp?.selectedWorkflow, "test-workflow.md")
        XCTAssertEqual(lookedUp?.confidence ?? 0, 0.9, accuracy: 0.001)
    }

    func testCacheMiss() {
        let lookedUp = manager.lookupCache(taskHash: "nonexistent")
        XCTAssertNil(lookedUp)
    }

    func testCacheExpiredEntry() {
        let expiredEntry = ZenflowRouterCacheEntry(
            selectedWorkflow: "old-workflow.md",
            confidence: 0.5,
            expiresAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )

        manager.setCache(taskHash: "expired123", entry: expiredEntry)
        let lookedUp = manager.lookupCache(taskHash: "expired123")

        XCTAssertNil(lookedUp)
    }

    func testClearCache() {
        let entry = ZenflowRouterCacheEntry(
            selectedWorkflow: "test.md",
            confidence: 0.8,
            expiresAt: Date().addingTimeInterval(3600)
        )

        manager.setCache(taskHash: "abc", entry: entry)
        manager.clearCache()

        XCTAssertNil(manager.lookupCache(taskHash: "abc"))
    }

    // MARK: - Decision Log

    func testLogDecision() {
        let decision = ZenflowRouterDecision(
            timestamp: Date(),
            taskHash: "hash123",
            selectedWorkflow: "code-review.md",
            confidence: 0.95,
            classifierUsed: "gpt-4o"
        )

        manager.logDecision(decision)
        let recent = manager.recentDecisions(limit: 10)

        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.taskHash, "hash123")
        XCTAssertEqual(recent.first?.selectedWorkflow, "code-review.md")
    }

    func testDecisionLogRingBuffer() {
        // Add more than 50 decisions
        for i in 0..<55 {
            let decision = ZenflowRouterDecision(
                timestamp: Date(),
                taskHash: "hash\(i)",
                selectedWorkflow: "workflow\(i).md",
                confidence: Double(i) / 100.0,
                classifierUsed: "gpt-4o"
            )
            manager.logDecision(decision)
        }

        let recent = manager.recentDecisions(limit: 100)
        XCTAssertEqual(recent.count, 50)

        // Should contain the most recent decisions (highest indices)
        let firstHash = recent.first?.taskHash
        XCTAssertEqual(firstHash, "hash54")
    }

    func testRecentDecisionsLimit() {
        for i in 0..<10 {
            let decision = ZenflowRouterDecision(
                timestamp: Date(),
                taskHash: "hash\(i)",
                selectedWorkflow: "workflow\(i).md",
                confidence: 0.5,
                classifierUsed: "gpt-4o"
            )
            manager.logDecision(decision)
        }

        let recent = manager.recentDecisions(limit: 5)
        XCTAssertEqual(recent.count, 5)
    }

    // MARK: - Routing

    func testRouteWhenDisabled() {
        let config = ZenflowRouterConfig(
            enabled: false,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: []
        )
        try? manager.saveConfig(config)

        let result = manager.route(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test",
            shimClassifierAvailable: true
        )

        XCTAssertEqual(result, "default.md")
    }

    func testRouteClassifierUnavailable() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )
        try? manager.saveConfig(config)

        let result = manager.route(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test",
            shimClassifierAvailable: false
        )

        XCTAssertEqual(result, "default.md")
    }

    func testRouteCacheHit() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )
        try? manager.saveConfig(config)

        let taskHash = ZenflowRouterManager.hashTask(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test"
        )

        let entry = ZenflowRouterCacheEntry(
            selectedWorkflow: "cached-workflow.md",
            confidence: 0.9,
            expiresAt: Date().addingTimeInterval(3600)
        )
        manager.setCache(taskHash: taskHash, entry: entry)

        let result = manager.route(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test",
            shimClassifierAvailable: true
        )

        XCTAssertEqual(result, "cached-workflow.md")
    }

    func testRouteCacheMissWithClassifierAvailableReturnsDefault() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )
        try? manager.saveConfig(config)

        let result = manager.route(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test",
            shimClassifierAvailable: true
        )

        // Caller is expected to invoke the classifier asynchronously and call
        // applyClassifierResult with the response.
        XCTAssertEqual(result, "default.md")
    }

    func testRouteCacheDisabledSkipsCacheLookup() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: false,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )
        try? manager.saveConfig(config)

        let taskHash = ZenflowRouterManager.hashTask(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test"
        )
        let entry = ZenflowRouterCacheEntry(
            selectedWorkflow: "cached-workflow.md",
            confidence: 0.9,
            expiresAt: Date().addingTimeInterval(3600)
        )
        manager.setCache(taskHash: taskHash, entry: entry)

        let result = manager.route(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test",
            shimClassifierAvailable: true
        )

        // Cache disabled: should ignore cached entry and return default
        XCTAssertEqual(result, "default.md")
    }

    func testRouteWithoutConfigReturnsEmptyString() {
        try? manager.deleteConfig()

        let result = manager.route(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test",
            shimClassifierAvailable: true
        )

        XCTAssertEqual(result, "")
    }

    func testApplyClassifierResult() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "code-review.md", cost: 1.0, quality: 2.0, card: "Code review"),
                ZenflowRouterCandidate(workflowFileName: "security-audit.md", cost: 2.0, quality: 3.0, card: "Security audit")
            ]
        )
        try? manager.saveConfig(config)

        let result = manager.applyClassifierResult(
            classifierOutput: "code-review.md",
            taskTitle: "Review this PR",
            taskDescription: "Please review the code changes",
            projectPath: "/test",
            classifierModel: "gpt-4o"
        )

        XCTAssertEqual(result, "code-review.md")

        // Verify decision was logged
        let recent = manager.recentDecisions(limit: 1)
        XCTAssertEqual(recent.first?.selectedWorkflow, "code-review.md")
    }

    func testApplyClassifierResultFallback() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )
        try? manager.saveConfig(config)

        let result = manager.applyClassifierResult(
            classifierOutput: "unknown-workflow.md",
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test",
            classifierModel: "gpt-4o"
        )

        // Should fallback to default
        XCTAssertEqual(result, "default.md")
    }

    func testApplyClassifierResultCachesWith24HourTTL() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )
        try? manager.saveConfig(config)

        let before = Date()
        _ = manager.applyClassifierResult(
            classifierOutput: "a.md",
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test-cache-ttl",
            classifierModel: "gpt-4o"
        )

        let taskHash = ZenflowRouterManager.hashTask(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test-cache-ttl"
        )
        let entry = manager.lookupCache(taskHash: taskHash)
        XCTAssertNotNil(entry)

        let expectedExpiry = before.addingTimeInterval(24 * 60 * 60)
        let actualExpiry = entry!.expiresAt
        XCTAssertEqual(
            actualExpiry.timeIntervalSince(expectedExpiry),
            0,
            accuracy: 5.0,
            "Cache entry should expire ~24h after caching"
        )

        // Entry should still be valid for at least 23h
        let hoursUntilExpiry = actualExpiry.timeIntervalSince(Date()) / 3600
        XCTAssertGreaterThan(hoursUntilExpiry, 23.0)
    }

    func testApplyClassifierResultLogsDecision() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "claude-sonnet-4",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "a.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "b.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        )
        try? manager.saveConfig(config)

        _ = manager.applyClassifierResult(
            classifierOutput: "a.md",
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test-log",
            classifierModel: "claude-sonnet-4"
        )

        let recent = manager.recentDecisions(limit: 1)
        XCTAssertEqual(recent.first?.selectedWorkflow, "a.md")
        XCTAssertEqual(recent.first?.classifierUsed, "claude-sonnet-4")

        let expectedHash = ZenflowRouterManager.hashTask(
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test-log"
        )
        XCTAssertEqual(recent.first?.taskHash, expectedHash)
    }

    func testApplyClassifierResultMatchesCandidateWithHyphenNormalization() {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.7,
            defaultWorkflow: "default.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "code-review.md", cost: 1.0, quality: 2.0, card: "Code review"),
                ZenflowRouterCandidate(workflowFileName: "security-audit.md", cost: 2.0, quality: 3.0, card: "Security audit")
            ]
        )
        try? manager.saveConfig(config)

        // Classifier output with surrounding whitespace and mixed case
        let result = manager.applyClassifierResult(
            classifierOutput: "  CODE-REVIEW.md  ",
            taskTitle: "Test",
            taskDescription: "Description",
            projectPath: "/test",
            classifierModel: "gpt-4o"
        )

        XCTAssertEqual(result, "code-review.md")
    }

    // MARK: - Hash

    func testHashTaskConsistency() {
        let hash1 = ZenflowRouterManager.hashTask(
            taskTitle: "Test Title",
            taskDescription: "Test Description",
            projectPath: "/path/to/project"
        )
        let hash2 = ZenflowRouterManager.hashTask(
            taskTitle: "Test Title",
            taskDescription: "Test Description",
            projectPath: "/path/to/project"
        )

        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 64) // SHA-256 hex string length
    }

    func testHashTaskDifferentInputs() {
        let hash1 = ZenflowRouterManager.hashTask(
            taskTitle: "Title A",
            taskDescription: "Description A",
            projectPath: "/project/a"
        )
        let hash2 = ZenflowRouterManager.hashTask(
            taskTitle: "Title B",
            taskDescription: "Description A",
            projectPath: "/project/a"
        )

        XCTAssertNotEqual(hash1, hash2)
    }
}
