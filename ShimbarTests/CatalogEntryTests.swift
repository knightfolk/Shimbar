import XCTest
@testable import Shimbar

final class CatalogEntryTests: XCTestCase {

    private func makeModel(
        model: String = "test-model",
        displayName: String = "Test Model",
        maxContextLimit: Int? = nil,
        noImageSupport: Bool = false
    ) -> ShimModel {
        ShimModel(
            slug: model,
            model: model,
            displayName: displayName,
            provider: "openai",
            baseUrl: "https://api.example.com/v1",
            apiKey: "sk-test",
            maxContextLimit: maxContextLimit,
            noImageSupport: noImageSupport
        )
    }

    // MARK: - Context Window Defaults

    func testDefaultContextClaude() {
        let m = makeModel(model: "claude-sonnet-4", displayName: "Claude Sonnet 4")
        XCTAssertEqual(CatalogEntry.defaultContext(for: m), 200_000)
    }

    func testDefaultContextGPT5() {
        let m = makeModel(model: "gpt-5", displayName: "GPT-5")
        XCTAssertEqual(CatalogEntry.defaultContext(for: m), 400_000)
    }

    func testDefaultContextGemini() {
        let m = makeModel(model: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro")
        XCTAssertEqual(CatalogEntry.defaultContext(for: m), 1_000_000)
    }

    func testDefaultContextGeneric() {
        let m = makeModel(model: "deepseek-v3", displayName: "DeepSeek V3")
        XCTAssertEqual(CatalogEntry.defaultContext(for: m), 128_000)
    }

    func testDefaultContextRespectsMaxContextLimit() {
        let m = makeModel(model: "claude-sonnet-4", displayName: "Claude Sonnet 4", maxContextLimit: 50_000)
        XCTAssertEqual(CatalogEntry.defaultContext(for: m), 50_000)
    }

    func testDefaultContextZeroMaxContextLimitFallsBackToFamily() {
        let m = makeModel(model: "claude-sonnet-4", displayName: "Claude Sonnet 4", maxContextLimit: 0)
        XCTAssertEqual(CatalogEntry.defaultContext(for: m), 200_000)
    }

    // MARK: - Truncation / Auto-Compact Math

    func testTruncationLimitClaude() {
        let ctx = 200_000
        let trunc = CatalogEntry.truncationLimit(context: ctx)
        XCTAssertEqual(trunc, 64_000)
    }

    func testTruncationLimitSmallContext() {
        let ctx = 8_000
        let trunc = CatalogEntry.truncationLimit(context: ctx)
        XCTAssertEqual(trunc, 8_000)
    }

    func testTruncationLimitGemini() {
        let ctx = 1_000_000
        let trunc = CatalogEntry.truncationLimit(context: ctx)
        XCTAssertEqual(trunc, 64_000)
    }

    func testAutoCompactLimitClaude() {
        let ctx = 200_000
        let compact = CatalogEntry.autoCompactLimit(context: ctx)
        XCTAssertEqual(compact, 160_000)
    }

    func testAutoCompactLimitMinimum() {
        let ctx = 8_000
        let compact = CatalogEntry.autoCompactLimit(context: ctx)
        XCTAssertEqual(compact, 8_000)
    }

    func testAutoCompactLimitGemini() {
        let ctx = 1_000_000
        let compact = CatalogEntry.autoCompactLimit(context: ctx)
        XCTAssertEqual(compact, 800_000)
    }

    // MARK: - Priority Inversion

    func testPriorityFirstModel() {
        XCTAssertEqual(CatalogEntry.priority(index: 0), 1000)
    }

    func testPriorityLaterModel() {
        XCTAssertEqual(CatalogEntry.priority(index: 5), 995)
    }

    func testPriorityNeverBelowOne() {
        XCTAssertEqual(CatalogEntry.priority(index: 2000), 1)
    }

    // MARK: - Reasoning Inference

    func testReasoningEffortXHigh() {
        XCTAssertEqual(CatalogEntry.reasoningEffort(displayName: "Claude Opus xhigh"), "xhigh")
    }

    func testReasoningEffortXHighHyphen() {
        XCTAssertEqual(CatalogEntry.reasoningEffort(displayName: "GPT-5 x-high"), "xhigh")
    }

    func testReasoningEffortHigh() {
        XCTAssertEqual(CatalogEntry.reasoningEffort(displayName: "Claude Sonnet High"), "high")
    }

    func testReasoningEffortMedium() {
        XCTAssertEqual(CatalogEntry.reasoningEffort(displayName: "GPT-5 Medium Reasoning"), "medium")
    }

    func testReasoningEffortLow() {
        XCTAssertEqual(CatalogEntry.reasoningEffort(displayName: "GPT-5 low"), "low")
    }

    func testReasoningEffortDefault() {
        XCTAssertEqual(CatalogEntry.reasoningEffort(displayName: "GPT-4o"), "medium")
    }

    // MARK: - Make Entry

    func testMakeEntrySetsSlug() {
        let m = makeModel(model: "gpt-5")
        let entry = CatalogEntry.makeEntry(for: m, index: 0)
        XCTAssertEqual(entry["slug"] as? String, "gpt-5")
    }

    func testMakeEntryImageSupport() {
        let withImages = makeModel(noImageSupport: false)
        let entryImages = CatalogEntry.makeEntry(for: withImages, index: 0)
        let modalities = entryImages["input_modalities"] as? [String]
        XCTAssertEqual(modalities, ["text", "image"])

        let noImages = makeModel(noImageSupport: true)
        let entryNoImages = CatalogEntry.makeEntry(for: noImages, index: 0)
        let modalitiesNo = entryNoImages["input_modalities"] as? [String]
        XCTAssertEqual(modalitiesNo, ["text"])
    }
}
