import XCTest
@testable import Shimbar

final class ChatGPTCatalogTests: XCTestCase {

    private var envSnapshot: [String: String] = [:]

    override func setUp() {
        super.setUp()
        envSnapshot = ProcessInfo.processInfo.environment
        unsetenv("CODEX_SHIM_MODELS_CACHE_PATH")
    }

    override func tearDown() {
        for (key, value) in envSnapshot {
            setenv(key, value, 1)
        }
        if envSnapshot["CODEX_SHIM_MODELS_CACHE_PATH"] == nil {
            unsetenv("CODEX_SHIM_MODELS_CACHE_PATH")
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCacheFile(at url: URL, json: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try json.data(using: .utf8)!.write(to: url)
    }

    // MARK: - Slug Classification

    func testIsChatGPTPassthroughSlugAcceptsOpenAIPrefix() {
        XCTAssertTrue(ChatGPTCatalog.isChatGPTPassthroughSlug("openai-gpt-5-5"))
        XCTAssertTrue(ChatGPTCatalog.isChatGPTPassthroughSlug("openai-gpt-4o"))
    }

    func testIsChatGPTPassthroughSlugRejectsUnknownSlugs() {
        XCTAssertFalse(ChatGPTCatalog.isChatGPTPassthroughSlug("gpt-9.0"))
        XCTAssertFalse(ChatGPTCatalog.isChatGPTPassthroughSlug(""))
        XCTAssertFalse(ChatGPTCatalog.isChatGPTPassthroughSlug("claude-opus"))
    }

    func testIsChatGPTPassthroughSlugAcceptsCacheEntries() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-catalog-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("models_cache.json")
        try makeCacheFile(
            at: url,
            json: #"""
            { "models": [
              { "slug": "gpt-5.5", "display_name": "GPT-5.5" },
              { "slug": "gpt-5.4-mini", "display_name": "GPT-5.4-Mini" }
            ] }
            """#
        )
        setenv("CODEX_SHIM_MODELS_CACHE_PATH", url.path, 1)
        XCTAssertTrue(ChatGPTCatalog.isChatGPTPassthroughSlug("gpt-5.5"))
        XCTAssertTrue(ChatGPTCatalog.isChatGPTPassthroughSlug("gpt-5.4-mini"))
    }

    func testCacheHidesEntriesWithVisibilityHidden() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-catalog-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("models_cache.json")
        try makeCacheFile(
            at: url,
            json: #"""
            { "models": [
              { "slug": "gpt-5.5", "display_name": "GPT-5.5", "visibility": "list" },
              { "slug": "gpt-5.4", "display_name": "Hidden", "visibility": "hidden" }
            ] }
            """#
        )
        setenv("CODEX_SHIM_MODELS_CACHE_PATH", url.path, 1)
        XCTAssertTrue(ChatGPTCatalog.isChatGPTPassthroughSlug("gpt-5.5"))
        XCTAssertFalse(ChatGPTCatalog.isChatGPTPassthroughSlug("gpt-5.4"))
    }

    func testCacheFiltersNonGPTOrCodexPrefixes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-catalog-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("models_cache.json")
        try makeCacheFile(
            at: url,
            json: #"""
            { "models": [
              { "slug": "claude-opus" },
              { "slug": "gemini-1.5" },
              { "slug": "gpt-5.5" }
            ] }
            """#
        )
        setenv("CODEX_SHIM_MODELS_CACHE_PATH", url.path, 1)
        let slugs = ChatGPTCatalog.loadSlugs()
        XCTAssertEqual(slugs, Set(["gpt-5.5"]))
    }

    // MARK: - Fallback slugs

    func testFallbackSlugsWhenCacheMissing() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-catalog-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("models_cache.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        setenv("CODEX_SHIM_MODELS_CACHE_PATH", url.path, 1)
        let slugs = ChatGPTCatalog.loadSlugs()
        XCTAssertEqual(slugs, Set(ChatGPTCatalog.fallbackSlugs))
    }

    func testFallbackSlugsWhenCacheMalformed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-catalog-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("models_cache.json")
        try makeAuthFile(at: url, json: "{not valid")
        setenv("CODEX_SHIM_MODELS_CACHE_PATH", url.path, 1)
        let slugs = ChatGPTCatalog.loadSlugs()
        XCTAssertEqual(slugs, Set(ChatGPTCatalog.fallbackSlugs))
    }

    func testFallbackSlugsWhenCacheEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-catalog-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("models_cache.json")
        try makeCacheFile(at: url, json: "{ \"models\": [] }")
        setenv("CODEX_SHIM_MODELS_CACHE_PATH", url.path, 1)
        let slugs = ChatGPTCatalog.loadSlugs()
        XCTAssertEqual(slugs, Set(ChatGPTCatalog.fallbackSlugs))
    }

    func testFallbackEntriesHaveDisplayNames() {
        let entries = ChatGPTCatalog.fallbackEntries()
        for entry in entries {
            XCTAssertFalse(entry.displayName.isEmpty)
            XCTAssertEqual(entry.displayName,
                           ChatGPTCatalog.fallbackDisplayNames[entry.slug] ?? entry.slug)
        }
    }

    // MARK: - Display Names

    func testLoadDisplayNamesFromCache() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-catalog-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("models_cache.json")
        try makeCacheFile(
            at: url,
            json: #"""
            { "models": [
              { "slug": "gpt-5.5", "display_name": "GPT 5.5 (Custom)" }
            ] }
            """#
        )
        setenv("CODEX_SHIM_MODELS_CACHE_PATH", url.path, 1)
        let names = ChatGPTCatalog.loadDisplayNames()
        XCTAssertEqual(names["gpt-5.5"], "GPT 5.5 (Custom)")
    }

    // MARK: - upstreamModel

    func testUpstreamModelForOpenAIPrefix() {
        XCTAssertEqual(
            ChatGPTCatalog.upstreamModel(for: "openai-gpt-5-5"),
            ChatGPTCatalog.defaultUpstreamModel
        )
    }

    func testUpstreamModelForKnownSlug() {
        XCTAssertEqual(ChatGPTCatalog.upstreamModel(for: "gpt-5.5"), "gpt-5.5")
    }

    func testUpstreamModelForUnknownSlugFallsBack() {
        XCTAssertEqual(
            ChatGPTCatalog.upstreamModel(for: "unknown-slug"),
            ChatGPTCatalog.defaultUpstreamModel
        )
    }

    // MARK: - Cache Env Override

    func testEnvOverrideChangesCatalogPath() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-catalog-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("models_cache.json")
        setenv("CODEX_SHIM_MODELS_CACHE_PATH", url.path, 1)
        XCTAssertEqual(ChatGPTCatalog.modelsCachePath.path, url.path)
    }

    // MARK: - Helpers

    private func makeAuthFile(at url: URL, json: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try json.data(using: .utf8)!.write(to: url)
    }
}
