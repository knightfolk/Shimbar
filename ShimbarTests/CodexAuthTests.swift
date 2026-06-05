import XCTest
@testable import Shimbar

final class CodexAuthTests: XCTestCase {

    private var envSnapshot: [String: String] = [:]
    private var savedAuthPath: String?

    override func setUp() {
        super.setUp()
        envSnapshot = ProcessInfo.processInfo.environment
        savedAuthPath = ProcessInfo.processInfo.environment["CODEX_SHIM_AUTH_PATH"]
        try? KeychainManager.deleteKey(forProvider: CodexAuthStore.keychainAccount)
    }

    override func tearDown() {
        for (key, value) in envSnapshot {
            setenv(key, value, 1)
        }
        if let saved = savedAuthPath {
            setenv("CODEX_SHIM_AUTH_PATH", saved, 1)
        } else {
            unsetenv("CODEX_SHIM_AUTH_PATH")
        }
        try? KeychainManager.deleteKey(forProvider: CodexAuthStore.keychainAccount)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeAuthFile(at url: URL, json: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try json.data(using: .utf8)!.write(to: url)
    }

    // MARK: - load() / loadAccessToken()

    func testLoadReturnsNilWhenFileMissing() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        let store = CodexAuthStore(authPath: url)
        XCTAssertNil(store.load())
        XCTAssertNil(store.loadAccessToken())
    }

    func testLoadReturnsNilForMalformedJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(at: url, json: "{not valid json")
        let store = CodexAuthStore(authPath: url)
        XCTAssertNil(store.load())
        XCTAssertNil(store.loadAccessToken())
    }

    func testLoadAccessTokenFromTokensBlock() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(
            at: url,
            json: #"""
            {
              "tokens": {
                "access_token": "from-nested",
                "refresh_token": "refresh-1",
                "account_id": "acct-123"
              }
            }
            """#
        )
        let store = CodexAuthStore(authPath: url)
        XCTAssertEqual(store.loadAccessToken(), "from-nested")
        XCTAssertEqual(store.loadAccountID(), "acct-123")
    }

    func testLoadAccessTokenFromTopLevel() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(
            at: url,
            json: #"""
            { "access_token": "from-top-level", "account_id": "acct-9" }
            """#
        )
        let store = CodexAuthStore(authPath: url)
        XCTAssertEqual(store.loadAccessToken(), "from-top-level")
        XCTAssertEqual(store.loadAccountID(), "acct-9")
    }

    func testEmptyAccessTokenIsConsideredMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(
            at: url,
            json: #"""
            { "tokens": { "access_token": "", "account_id": "acct" } }
            """#
        )
        let store = CodexAuthStore(authPath: url)
        XCTAssertNil(store.loadAccessToken())
        XCTAssertTrue(store.isAuthMissingOrInvalid())
    }

    // MARK: - Env var override

    func testEnvVarOverrideChangesAuthPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(
            at: url,
            json: #"{ "tokens": { "access_token": "env-tok", "account_id": "env-acct" } }"#
        )
        setenv("CODEX_SHIM_AUTH_PATH", url.path, 1)
        let store = CodexAuthStore()
        XCTAssertEqual(store.authPath.path, url.path)
        XCTAssertEqual(store.loadAccessToken(), "env-tok")
    }

    // MARK: - Expired token

    func testExpiredTokenIsReported() {
        let auth = CodexAuth(
            accessToken: "tok",
            refreshToken: nil,
            accountID: nil,
            expiresAt: Date().timeIntervalSince1970 - 1000,
            tokens: nil
        )
        XCTAssertTrue(CodexAuthStore.isExpired(auth))

        let future = CodexAuth(
            accessToken: "tok",
            refreshToken: nil,
            accountID: nil,
            expiresAt: Date().timeIntervalSince1970 + 1000,
            tokens: nil
        )
        XCTAssertFalse(CodexAuthStore.isExpired(future))

        let noExpiry = CodexAuth(
            accessToken: "tok",
            refreshToken: nil,
            accountID: nil,
            expiresAt: nil,
            tokens: nil
        )
        XCTAssertFalse(CodexAuthStore.isExpired(noExpiry))
    }

    // MARK: - Refresh rotation

    func testRotatePersistsNewTokensAndUpdatesKeychain() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(
            at: url,
            json: #"""
            {
              "tokens": {
                "access_token": "old-access",
                "refresh_token": "old-refresh",
                "account_id": "old-acct"
              }
            }
            """#
        )
        let store = CodexAuthStore(authPath: url)
        XCTAssertEqual(store.loadAccessToken(), "old-access")

        try store.rotate(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            accountID: "new-acct",
            expiresAt: Date().timeIntervalSince1970 + 3600
        )

        XCTAssertEqual(store.loadAccessToken(), "new-access")
        XCTAssertEqual(store.loadAccountID(), "new-acct")

        let stored = KeychainManager.getKey(forProvider: CodexAuthStore.keychainAccount)
        XCTAssertEqual(stored, "new-access")

        let roundTrip = try JSONDecoder().decode(
            CodexAuth.self,
            from: try Data(contentsOf: url)
        )
        XCTAssertEqual(roundTrip.tokens?.accessToken, "new-access")
        XCTAssertEqual(roundTrip.tokens?.refreshToken, "new-refresh")
        XCTAssertEqual(roundTrip.tokens?.accountID, "new-acct")
    }

    func testRotateCreatesAuthFileWhenMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        let store = CodexAuthStore(authPath: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        try store.rotate(
            accessToken: "first-access",
            refreshToken: "first-refresh",
            accountID: "first-acct"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.loadAccessToken(), "first-access")
        XCTAssertEqual(store.loadAccountID(), "first-acct")
    }

    // MARK: - Clear

    func testClearRemovesFileAndKeychainEntry() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(
            at: url,
            json: #"""
            { "tokens": { "access_token": "to-be-cleared", "account_id": "x" } }
            """#
        )
        try KeychainManager.saveKey("to-be-cleared", forProvider: CodexAuthStore.keychainAccount)

        let store = CodexAuthStore(authPath: url)
        try store.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(KeychainManager.getKey(forProvider: CodexAuthStore.keychainAccount))
    }
}
