import Foundation

// MARK: - CodexAuth

/// Reads and caches the user's ChatGPT subscription auth from `~/.codex/auth.json`.
///
/// Mirrors the Python ``codex_shim.settings.chatgpt_passthrough_available`` probe:
/// when the env var `CODEX_SHIM_DISABLE_CHATGPT` is set to a truthy value, or the
/// auth file is missing/malformed, or the file holds no usable `access_token`,
/// the ChatGPT passthrough is considered unavailable. On a successful read the
/// access token is mirrored into the macOS Keychain so background services can
/// re-use it without re-reading the file. Refresh-rotation writes the new
/// token back to the on-disk JSON so the on-disk layout in `~/.codex/` is
/// preserved.
struct CodexAuth: Codable, Equatable, Sendable {

    /// Tokens block at `~/.codex/auth.json.tokens`.
    struct Tokens: Codable, Equatable, Sendable {
        var accessToken: String?
        var refreshToken: String?
        var accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case accountID = "account_id"
        }
    }

    /// The access token used to authorize the `Authorization: Bearer …` header.
    var accessToken: String?

    /// The refresh token; present when the user logged in with `codex login`.
    var refreshToken: String?

    /// The ChatGPT account identifier sent in the `chatgpt-account-id` header.
    var accountID: String?

    /// Optional expiry timestamp (seconds since the unix epoch).
    var expiresAt: Double?

    /// Tokens block, populated when the JSON contains a nested `tokens` object.
    var tokens: Tokens?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
        case expiresAt = "expires_at"
        case tokens
    }
}

// MARK: - CodexAuthStore

/// Reads and writes `~/.codex/auth.json`, mirroring access tokens into the
/// Keychain via ``KeychainManager`` for safe re-use by background services.
struct CodexAuthStore: Sendable {

    /// The Keychain account used to mirror the Codex access token.
    static let keychainAccount = "codex.chatgpt.access_token"

    /// The on-disk path to `auth.json`. Defaults to `~/.codex/auth.json`; can be
    /// overridden with the `CODEX_SHIM_AUTH_PATH` environment variable (used by
    /// tests).
    let authPath: URL

    /// Creates a new store pointing at the given `authPath`.
    /// - Parameter authPath: Absolute path to the auth.json file.
    init(authPath: URL? = nil) {
        if let authPath {
            self.authPath = authPath
        } else if let override = ProcessInfo.processInfo.environment["CODEX_SHIM_AUTH_PATH"],
                  !override.isEmpty {
            self.authPath = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else {
            self.authPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex")
                .appendingPathComponent("auth.json")
        }
    }

    // MARK: - Load

    /// Reads the auth file and returns a decoded ``CodexAuth`` value.
    /// - Returns: The decoded auth, or `nil` when the file is missing or
    ///   malformed.
    func load() -> CodexAuth? {
        guard FileManager.default.fileExists(atPath: authPath.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: authPath)
            return try Self.decoder.decode(CodexAuth.self, from: data)
        } catch {
            DebugLogger.log("CodexAuthStore: failed to parse \(authPath.path): \(error)")
            return nil
        }
    }

    /// Returns the access token from the on-disk auth file.
    /// - Returns: The token string, or `nil` when not present/usable.
    func loadAccessToken() -> String? {
        guard let auth = load() else { return nil }
        return Self.effectiveAccessToken(from: auth)
    }

    /// Returns the `chatgpt-account-id` from the on-disk auth file.
    /// - Returns: The account id, or an empty string when absent.
    func loadAccountID() -> String {
        load()?.accountID ?? load()?.tokens?.accountID ?? ""
    }

    /// Returns `true` when the file is missing, malformed, has no tokens block,
    /// or has an empty `access_token` field. Matches the Python probe's
    /// semantics so the Swift behaviour stays in lockstep.
    func isAuthMissingOrInvalid() -> Bool {
        guard FileManager.default.fileExists(atPath: authPath.path) else {
            return true
        }
        guard let data = try? Data(contentsOf: authPath) else {
            return true
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return true
        }
        guard let tokens = json["tokens"] as? [String: Any] else {
            return true
        }
        guard let access = tokens["access_token"] as? String, !access.isEmpty else {
            return true
        }
        return false
    }

    // MARK: - Save / Rotate

    /// Writes the auth back to disk and mirrors the new access token into the
    /// Keychain. Atomic on-disk write so concurrent `codex login` invocations
    /// don't truncate the file.
    /// - Parameter auth: The new auth payload.
    func save(_ auth: CodexAuth) throws {
        let encoder = Self.encoder
        let data = try encoder.encode(auth)
        try FileManager.default.createDirectory(
            at: authPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: authPath, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authPath.path)
        if let access = Self.effectiveAccessToken(from: auth) {
            try? KeychainManager.saveKey(access, forProvider: Self.keychainAccount)
        }
    }

    /// Replaces the on-disk `access_token` and `refresh_token` (refresh
    /// rotation), persisting back to disk and to the Keychain.
    /// - Parameters:
    ///   - accessToken: The freshly issued access token.
    ///   - refreshToken: The new refresh token (may be the same as before).
    ///   - accountID: The account id; defaults to the existing value.
    ///   - expiresAt: Optional epoch seconds for token expiry.
    func rotate(
        accessToken: String,
        refreshToken: String?,
        accountID: String? = nil,
        expiresAt: Double? = nil
    ) throws {
        var auth = load() ?? CodexAuth()
        auth.accessToken = accessToken
        auth.refreshToken = refreshToken ?? auth.refreshToken
        if let accountID, !accountID.isEmpty {
            auth.accountID = accountID
        } else if auth.accountID == nil {
            auth.accountID = load()?.tokens?.accountID
        }
        auth.expiresAt = expiresAt ?? auth.expiresAt
        var tokens = auth.tokens ?? CodexAuth.Tokens()
        tokens.accessToken = accessToken
        tokens.refreshToken = refreshToken ?? tokens.refreshToken
        if let accountID, !accountID.isEmpty {
            tokens.accountID = accountID
        } else if tokens.accountID == nil {
            tokens.accountID = auth.accountID
        }
        auth.tokens = tokens
        try save(auth)
    }

    /// Deletes the on-disk file and the mirrored Keychain entry.
    func clear() throws {
        if FileManager.default.fileExists(atPath: authPath.path) {
            try FileManager.default.removeItem(at: authPath)
        }
        try? KeychainManager.deleteKey(forProvider: Self.keychainAccount)
    }

    // MARK: - Helpers

    static func effectiveAccessToken(from auth: CodexAuth) -> String? {
        if let direct = auth.accessToken, !direct.isEmpty {
            return direct
        }
        if let nested = auth.tokens?.accessToken, !nested.isEmpty {
            return nested
        }
        return nil
    }

    /// Returns `true` if the auth has expired (only consulted when an
    /// `expires_at` field is present, matching the Python behaviour).
    static func isExpired(_ auth: CodexAuth, now: Date = Date()) -> Bool {
        guard let expiresAt = auth.expiresAt else {
            return false
        }
        return expiresAt <= now.timeIntervalSince1970
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
