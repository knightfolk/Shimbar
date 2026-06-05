import XCTest
@testable import Shimbar

final class CodexConfigPatcherTests: XCTestCase {

    private var tempDir: URL!
    private var configURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-patcher-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("config.toml")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func readConfig() -> String {
        (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
    }

    // MARK: - Fresh File

    func testInstallOnFreshFile() throws {
        try CodexConfigPatcher.install(
            defaultSlug: "claude-sonnet-4",
            catalogPath: "/home/user/.codex-shim/custom_model_catalog.json",
            port: 8765,
            configURL: configURL
        )

        let text = readConfig()
        XCTAssertTrue(text.contains("model = \"claude-sonnet-4\""))
        XCTAssertTrue(text.contains("model_provider = \"codex_shim\""))
        XCTAssertTrue(text.contains("model_catalog_json ="))
        XCTAssertTrue(text.contains("[model_providers.codex_shim]"))
        XCTAssertTrue(text.contains("base_url = \"http://127.0.0.1:8765/v1\""))
        XCTAssertTrue(text.contains("# >>> codex-shim managed >>>"))
        XCTAssertTrue(text.contains("# <<< codex-shim managed <<<"))
    }

    // MARK: - Existing Keys Preserved

    func testPreservesExistingContent() throws {
        let existing = """
        some_other_key = "hello"

        [other_section]
        foo = "bar"
        """
        try existing.data(using: .utf8)?.write(to: configURL, options: .atomic)

        try CodexConfigPatcher.install(
            defaultSlug: "gpt-5",
            catalogPath: "/path/to/catalog.json",
            port: 9000,
            configURL: configURL
        )

        let text = readConfig()
        XCTAssertTrue(text.contains("some_other_key = \"hello\""))
        XCTAssertTrue(text.contains("[other_section]"))
        XCTAssertTrue(text.contains("foo = \"bar\""))
        XCTAssertTrue(text.contains("model = \"gpt-5\""))
    }

    func testPreservesPreviousModelValue() throws {
        let existing = """
        model = "original-model"
        """
        try existing.data(using: .utf8)?.write(to: configURL, options: .atomic)

        try CodexConfigPatcher.install(
            defaultSlug: "new-model",
            catalogPath: "/path/catalog.json",
            port: 8765,
            configURL: configURL
        )

        let text = readConfig()
        XCTAssertTrue(text.contains("model = \"new-model\""))
    }

    // MARK: - Idempotent Re-Write

    func testIdempotentRewrite() throws {
        try CodexConfigPatcher.install(
            defaultSlug: "claude-sonnet-4",
            catalogPath: "/path/catalog.json",
            port: 8765,
            configURL: configURL
        )
        let first = readConfig()

        try CodexConfigPatcher.install(
            defaultSlug: "claude-sonnet-4",
            catalogPath: "/path/catalog.json",
            port: 8765,
            configURL: configURL
        )
        let second = readConfig()

        XCTAssertEqual(first, second)
    }

    // MARK: - Restore to Default

    func testRestoreRemovesManagedBlocks() throws {
        let original = """
        user_setting = "keep-me"

        [my_section]
        key = "value"
        """
        try original.data(using: .utf8)?.write(to: configURL, options: .atomic)

        try CodexConfigPatcher.install(
            defaultSlug: "gpt-5",
            catalogPath: "/path/catalog.json",
            port: 8765,
            configURL: configURL
        )
        let installed = readConfig()
        XCTAssertTrue(installed.contains("user_setting = \"keep-me\""))
        XCTAssertTrue(installed.contains("model = \"gpt-5\""))

        try CodexConfigPatcher.restore(configURL: configURL)
        let restored = readConfig()
        XCTAssertTrue(restored.contains("user_setting = \"keep-me\""))
        XCTAssertFalse(restored.contains("model = \"gpt-5\""))
        XCTAssertFalse(restored.contains("[model_providers.codex_shim]"))
        XCTAssertFalse(restored.contains("# >>> codex-shim managed >>>"))
    }

    func testRestoreOnEmptyFileDoesNotCrash() throws {
        XCTAssertNoThrow(try CodexConfigPatcher.restore(configURL: configURL))
    }

    // MARK: - Previous Top-Level Preservation

    func testPreviousTopLevelValuesPreservedAcrossCycles() throws {
        let original = """
        model = "original"
        model_provider = "openai"
        some_key = "value"
        """
        try original.data(using: .utf8)?.write(to: configURL, options: .atomic)

        try CodexConfigPatcher.install(
            defaultSlug: "new-model",
            catalogPath: "/path/catalog.json",
            port: 8765,
            configURL: configURL
        )

        try CodexConfigPatcher.restore(configURL: configURL)
        let restored = readConfig()

        XCTAssertTrue(restored.contains("model = \"original\""))
        XCTAssertTrue(restored.contains("model_provider = \"openai\""))
    }
}
