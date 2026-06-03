import XCTest
@testable import Shimbar

final class ModelsJsonManagerCRUDTests: XCTestCase {

    private var tempDir: URL!
    private var manager: ModelsJsonManager!

    override func setUp() async throws {
        try await super.setUp()

        let fm = FileManager.default
        tempDir = fm.temporaryDirectory.appendingPathComponent("ShimbarTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let jsonURL = tempDir.appendingPathComponent("models.json")
        manager = ModelsJsonManager(modelsJsonURL: jsonURL)
    }

    override func tearDown() async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: tempDir.path) {
            try fm.removeItem(at: tempDir)
        }
        manager = nil
        try await super.tearDown()
    }

    func testLoadFromEmptyDirectoryReturnsEmptyModels() throws {
        try manager.load()
        XCTAssertTrue(manager.models.isEmpty)
        XCTAssertFalse(manager.hasModels)
    }

    func testLoadParsesValidModelsJson() throws {
        let models = [
            ShimModel(slug: "gpt-4o", model: "gpt-4o", displayName: "GPT-4o", provider: "openai", baseUrl: "https://api.openai.com/v1", apiKey: "sk-test"),
            ShimModel(slug: "claude", model: "claude-sonnet-4", displayName: "Claude", provider: "anthropic", baseUrl: "https://api.anthropic.com/v1"),
        ]
        let file = ModelsFile(models: models)
        let data = try JSONEncoder().encode(file)
        try data.write(to: manager.modelsJsonURL, options: .atomic)

        try manager.load()
        XCTAssertEqual(manager.models.count, 2)
        XCTAssertEqual(manager.models[0].slug, "gpt-4o")
        XCTAssertEqual(manager.models[1].slug, "claude")
    }

    func testSaveAndReloadPreservesModels() throws {
        manager.models = [
            ShimModel(slug: "test-model", model: "test-model-id", displayName: "Test Model", provider: "openai", baseUrl: "https://api.test.com/v1", apiKey: "sk-key123", maxContextLimit: 128000, maxOutputTokens: 4096),
        ]
        try manager.save()

        let reloaded = ModelsJsonManager(modelsJsonURL: manager.modelsJsonURL)
        try reloaded.load()
        XCTAssertEqual(reloaded.models.count, 1)
        XCTAssertEqual(reloaded.models[0].slug, "test-model")
        XCTAssertEqual(reloaded.models[0].apiKey, "sk-key123")
        XCTAssertEqual(reloaded.models[0].maxContextLimit, 128000)
    }

    func testSaveCreatesBackup() throws {
        let bakURL = manager.modelsJsonURL.appendingPathExtension("bak")

        try "{\"models\":[]}".write(to: manager.modelsJsonURL, atomically: true, encoding: .utf8)

        manager.models = [ShimModel(slug: "new", model: "new", displayName: "New", provider: "openai", baseUrl: "https://api.test.com")]
        try manager.save()

        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path), "Backup file should exist after save")
        let backupContent = try String(contentsOf: bakURL)
        XCTAssertEqual(backupContent, "{\"models\":[]}")
    }

    func testLoadMalformedJsonClearsModelsAndThrows() throws {
        try "not valid json".write(to: manager.modelsJsonURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try manager.load())
        XCTAssertTrue(manager.models.isEmpty, "Malformed JSON should leave models empty after throw")
    }

    func testLoadEmptyJsonArray() throws {
        try "{\"models\":[]}".write(to: manager.modelsJsonURL, atomically: true, encoding: .utf8)

        try manager.load()
        XCTAssertTrue(manager.models.isEmpty)
        XCTAssertFalse(manager.hasModels)
    }

    func testHasModelsReturnsFalseWhenEmpty() throws {
        try manager.load()
        XCTAssertFalse(manager.hasModels)
    }

    func testHasModelsReturnsTrueWhenPopulated() throws {
        let file = ModelsFile(models: [
            ShimModel(slug: "x", model: "x", displayName: "X", provider: "openai", baseUrl: "https://api.test.com")
        ])
        let data = try JSONEncoder().encode(file)
        try data.write(to: manager.modelsJsonURL, options: .atomic)

        try manager.load()
        XCTAssertTrue(manager.hasModels)
    }

    func testEnsureDirectoryExistsCreatesParentDir() throws {
        let nestedURL = tempDir.appendingPathComponent("nested/sub/models.json")
        let nestedManager = ModelsJsonManager(modelsJsonURL: nestedURL)

        let dir = nestedURL.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        try nestedManager.load()
        XCTAssertTrue(nestedManager.models.isEmpty)
    }

    func testRouterConfigNilWhenAbsent() throws {
        try "{\"models\":[]}".write(to: manager.modelsJsonURL, atomically: true, encoding: .utf8)
        try manager.load()
        XCTAssertNil(manager.routerConfig)
    }

    func testRouterConfigLoadedFromDisk() throws {
        let json = """
        {
            "models": [],
            "router": {
                "enabled": true,
                "slug": "codex-auto",
                "display_name": "Auto",
                "classifier": "cheap",
                "threshold": 0.7,
                "default": "fallback",
                "cache": true,
                "candidates": [
                    {"slug": "a", "cost": 0.3, "supports_images": true, "card": "fast"}
                ]
            }
        }
        """
        try json.write(to: manager.modelsJsonURL, atomically: true, encoding: .utf8)
        try manager.load()

        XCTAssertNotNil(manager.routerConfig)
        XCTAssertTrue(manager.routerConfig!.enabled)
        XCTAssertEqual(manager.routerConfig!.slug, "codex-auto")
        XCTAssertEqual(manager.routerConfig!.candidates.count, 1)
        XCTAssertEqual(manager.routerConfig!.candidates[0].slug, "a")
    }

    func testRouterConfigSaveAndReload() throws {
        manager.models = [
            ShimModel(slug: "test", model: "test", displayName: "Test", provider: "openai", baseUrl: "https://api.test.com")
        ]
        manager.routerConfig = RouterConfig(
            enabled: false,
            slug: "codex-auto",
            displayName: "Auto",
            classifier: "cheap",
            threshold: 0.5,
            defaultModel: "test",
            cache: false,
            candidates: [
                RouterCandidate(slug: "test", cost: 1.0, supportsImages: false, card: "default")
            ]
        )
        try manager.save()

        let reloaded = ModelsJsonManager(modelsJsonURL: manager.modelsJsonURL)
        try reloaded.load()

        XCTAssertEqual(reloaded.models.count, 1)
        XCTAssertNotNil(reloaded.routerConfig)
        XCTAssertEqual(reloaded.routerConfig!.slug, "codex-auto")
        XCTAssertFalse(reloaded.routerConfig!.enabled)
        XCTAssertEqual(reloaded.routerConfig!.candidates.count, 1)
    }

    func testRouterConfigPreservedWhenModelsUpdated() throws {
        manager.models = []
        manager.routerConfig = RouterConfig(
            enabled: true,
            slug: "codex-auto",
            displayName: "Auto",
            classifier: "x",
            threshold: 0.7,
            defaultModel: "y",
            cache: true,
            candidates: []
        )
        try manager.save()

        manager.models = [ShimModel(slug: "new", model: "new", displayName: "New", provider: "openai", baseUrl: "")]
        try manager.save()

        let reloaded = ModelsJsonManager(modelsJsonURL: manager.modelsJsonURL)
        try reloaded.load()

        XCTAssertEqual(reloaded.models.count, 1)
        XCTAssertEqual(reloaded.models[0].slug, "new")
        XCTAssertNotNil(reloaded.routerConfig)
        XCTAssertTrue(reloaded.routerConfig!.enabled)
    }
}
