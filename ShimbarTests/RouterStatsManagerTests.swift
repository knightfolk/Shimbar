import XCTest
@testable import Shimbar

final class RouterStatsManagerTests: XCTestCase {

    private var manager: RouterStatsManager!

    override func setUp() {
        super.setUp()
        manager = RouterStatsManager.shared
        manager.clearStats()
    }

    override func tearDown() {
        manager.clearStats()
        super.tearDown()
    }

    // MARK: - Recording

    func testRecordEntryIncrementsTotal() {
        XCTAssertEqual(manager.getSummary().totalCalls, 0)

        manager.recordEntry(makeEntry(destination: "a.md"))
        XCTAssertEqual(manager.getSummary().totalCalls, 1)

        manager.recordEntry(makeEntry(destination: "b.md"))
        XCTAssertEqual(manager.getSummary().totalCalls, 2)
    }

    func testRecordEntryPersistsToDisk() {
        manager.recordEntry(makeEntry(destination: "persist-test.md"))

        let freshManager = RouterStatsManager.shared
        freshManager.clearStats()
        freshManager.recordEntry(makeEntry(destination: "persist-test.md"))

        let loaded = RouterStatsManager.shared
        XCTAssertEqual(loaded.getSummary().totalCalls, 1)
        XCTAssertEqual(loaded.getSummary().destinationCounts["persist-test.md"], 1)
    }

    // MARK: - Summary Aggregation

    func testSummaryDestinationCounts() {
        manager.recordEntry(makeEntry(destination: "a.md"))
        manager.recordEntry(makeEntry(destination: "a.md"))
        manager.recordEntry(makeEntry(destination: "b.md"))

        let summary = manager.getSummary()
        XCTAssertEqual(summary.destinationCounts["a.md"], 2)
        XCTAssertEqual(summary.destinationCounts["b.md"], 1)
        XCTAssertEqual(summary.mostUsedDestination, "a.md")
    }

    func testSummaryCacheHitRate() {
        manager.recordEntry(makeEntry(cacheHit: true))
        manager.recordEntry(makeEntry(cacheHit: true))
        manager.recordEntry(makeEntry(cacheHit: false))
        manager.recordEntry(makeEntry(cacheHit: false, reason: .classified))

        let summary = manager.getSummary()
        XCTAssertEqual(summary.cacheHitRate, 0.5, accuracy: 0.01)
    }

    func testSummaryAverageConfidence() {
        manager.recordEntry(makeEntry(confidence: 0.8, reason: .classified))
        manager.recordEntry(makeEntry(confidence: 0.6, reason: .lowConfidence))
        manager.recordEntry(makeEntry(confidence: 0.9, cacheHit: true, reason: .cacheHit))

        let summary = manager.getSummary()
        XCTAssertEqual(summary.averageConfidence, 0.7, accuracy: 0.01)
    }

    func testSummaryEmpty() {
        let summary = manager.getSummary()
        XCTAssertEqual(summary.totalCalls, 0)
        XCTAssertEqual(summary.cacheHitRate, 0)
        XCTAssertEqual(summary.averageConfidence, 0)
        XCTAssertTrue(summary.destinationCounts.isEmpty)
        XCTAssertNil(summary.mostUsedDestination)
    }

    // MARK: - Rotation Cap

    func testEntriesCapAt1000() {
        for i in 0..<1100 {
            manager.recordEntry(makeEntry(destination: "dest-\(i % 5).md"))
        }

        let allEntries = manager.allEntries()
        XCTAssertEqual(allEntries.count, 1000)
        XCTAssertEqual(manager.getSummary().totalCalls, 1000)
    }

    // MARK: - Clear

    func testClearStatsRemovesAll() {
        for i in 0..<50 {
            manager.recordEntry(makeEntry(destination: "dest-\(i).md"))
        }
        XCTAssertEqual(manager.getSummary().totalCalls, 50)

        manager.clearStats()
        XCTAssertEqual(manager.getSummary().totalCalls, 0)
        XCTAssertTrue(manager.allEntries().isEmpty)
        XCTAssertTrue(manager.getRecentEntries().isEmpty)
    }

    // MARK: - Recent Entries

    func testGetRecentEntriesReturnsInReverseOrder() {
        for i in 0..<10 {
            manager.recordEntry(makeEntry(destination: "dest-\(i).md"))
        }

        let recent = manager.getRecentEntries(limit: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0].selectedDestination, "dest-9.md")
        XCTAssertEqual(recent[1].selectedDestination, "dest-8.md")
        XCTAssertEqual(recent[2].selectedDestination, "dest-7.md")
    }

    func testGetRecentEntriesLimitCaps() {
        for _ in 0..<30 {
            manager.recordEntry(makeEntry())
        }

        let recent = manager.getRecentEntries(limit: 5)
        XCTAssertEqual(recent.count, 5)
    }

    // MARK: - Entries Since Date

    func testGetEntriesSinceDate() {
        let old = Date().addingTimeInterval(-3600)
        manager.recordEntry(RouterUsageEntry(
            timestamp: old,
            selectedDestination: "old.md",
            classifierUsed: "test",
            confidence: 0.5,
            taskHash: "old-hash",
            cacheHit: false,
            reason: .classified
        ))
        manager.recordEntry(makeEntry(destination: "new.md"))

        let since = Date().addingTimeInterval(-1800)
        let entries = manager.getEntriesSince(since)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].selectedDestination, "new.md")
    }

    // MARK: - Thread Safety

    func testConcurrentRecording() {
        let expectation = self.expectation(description: "concurrent writes")
        expectation.expectedFulfillmentCount = 10

        for i in 0..<10 {
            DispatchQueue.global().async {
                self.manager.recordEntry(self.makeEntry(destination: "concurrent-\(i).md"))
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5)
        XCTAssertEqual(manager.getSummary().totalCalls, 10)
    }

    // MARK: - Codable

    func testRouterUsageEntryCoding() throws {
        let entry = RouterUsageEntry(
            timestamp: Date(),
            selectedDestination: "test.md",
            classifierUsed: "gpt-4o",
            confidence: 0.85,
            taskHash: "abc123",
            cacheHit: false,
            reason: .classified
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RouterUsageEntry.self, from: data)

        XCTAssertEqual(decoded.selectedDestination, entry.selectedDestination)
        XCTAssertEqual(decoded.confidence, entry.confidence, accuracy: 0.001)
        XCTAssertEqual(decoded.cacheHit, entry.cacheHit)
        XCTAssertEqual(decoded.reason, entry.reason)
        XCTAssertEqual(decoded.classifierUsed, entry.classifierUsed)
        XCTAssertEqual(decoded.taskHash, entry.taskHash)
    }

    func testRouterDecisionReasonAllCasesCoding() throws {
        for reason in [RouterDecisionReason.classified, .lowConfidence, .disabled, .shimOffline, .classifierMissing, .parseError, .cacheHit, .unknown] {
            let entry = makeEntry(reason: reason)
            let data = try JSONEncoder().encode(entry)
            let decoded = try JSONDecoder().decode(RouterUsageEntry.self, from: data)
            XCTAssertEqual(decoded.reason, reason)
        }
    }

    // MARK: - Helpers

    private func makeEntry(
        destination: String = "default.md",
        confidence: Double = 0.75,
        cacheHit: Bool = false,
        reason: RouterDecisionReason = .classified
    ) -> RouterUsageEntry {
        RouterUsageEntry(
            timestamp: Date(),
            selectedDestination: destination,
            classifierUsed: "test-classifier",
            confidence: confidence,
            taskHash: UUID().uuidString,
            cacheHit: cacheHit,
            reason: reason
        )
    }
}
