import Foundation

// MARK: - ChatGPT Upstream

/// Forwards a Codex Responses request to the ChatGPT passthrough endpoint at
/// `https://chatgpt.com/backend-api/codex/responses`. The request body is
/// sanitised (shim-encrypted reasoning blocks are stripped) and the response
/// model is rewritten to the picker-visible slug so the picker UI gets back
/// the slug it asked for.
///
/// Streaming mode (`response.streamed == true`) emits the upstream SSE
/// byte-for-byte, with the response model rewritten on each `data:` line. The
/// non-streaming path returns the JSON payload as-is.
struct ChatGPTUpstream: Sendable {

    /// The base URL the upstream forwards to. Exposed as a static so tests can
    /// override it before constructing the request.
    static let responsesURL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    static let compactURL = URL(string: "https://chatgpt.com/backend-api/codex/responses/compact")!

    let authStore: CodexAuthStore
    let upstream: UpstreamClient

    init(
        authStore: CodexAuthStore = CodexAuthStore(),
        upstream: UpstreamClient = URLSessionUpstreamClient.shared
    ) {
        self.authStore = authStore
        self.upstream = upstream
    }

    // MARK: - Errors

    enum PassthroughError: LocalizedError {
        case authFileMissing(String)
        case authFileMalformed(String)
        case noAccessToken
        case upstreamNonSuccess(Int, String)
        case streamNotSupported

        var errorDescription: String? {
            switch self {
            case .authFileMissing(let path):
                return "~/.codex/auth.json not found at \(path)"
            case .authFileMalformed(let detail):
                return "auth.json is malformed: \(detail)"
            case .noAccessToken:
                return "auth.json has no access_token"
            case .upstreamNonSuccess(let status, let body):
                return "upstream returned status \(status): \(body)"
            case .streamNotSupported:
                return "stream() is not supported by this upstream"
            }
        }
    }

    // MARK: - Public

    /// Sends a Responses request upstream and returns the JSON payload. Use
    /// this for non-streaming (`stream: false`) requests and for
    /// `/v1/responses/compact` (which always asks for a single JSON payload).
    /// - Parameters:
    ///   - body: The Codex Responses request body, as decoded JSON.
    ///   - responseModelOverride: The picker-visible slug to rewrite into the
    ///     response payload so the picker sees the slug it asked for.
    ///   - compact: `true` when targeting `/v1/responses/compact`.
    /// - Returns: The decoded JSON payload from the upstream.
    func sendResponses(
        body: [String: Any],
        responseModelOverride: String? = nil,
        compact: Bool = false
    ) async throws -> [String: Any] {
        let token = try loadAccessToken()
        let accountID = authStore.loadAccountID()
        let request = try buildRequest(
            body: body,
            token: token,
            accountID: accountID,
            compact: compact,
            stream: false
        )
        let (data, response) = try await upstream.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PassthroughError.upstreamNonSuccess(response.statusCode, body)
        }
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let rewritten = Self.rewriteResponseModel(raw, to: responseModelOverride)
        return (rewritten as? [String: Any]) ?? raw
    }

    /// Streams the Responses request back to the caller. The returned stream
    /// emits the raw upstream bytes (SSE frames, already-prefixed with
    /// `data: `) so the picker can pipe them straight into its streaming
    /// response writer.
    /// - Parameters:
    ///   - body: The Codex Responses request body, as decoded JSON.
    ///   - responseModelOverride: The picker-visible slug to rewrite on every
    ///     SSE event.
    ///   - sessionID: Optional session id forwarded as the `session_id`
    ///     header.
    /// - Returns: An `AsyncThrowingStream` of SSE byte chunks ready to be
    ///   written to the client.
    func streamResponses(
        body: [String: Any],
        responseModelOverride: String? = nil,
        sessionID: String? = nil
    ) async throws -> AsyncThrowingStream<UInt8, Error> {
        let token = try loadAccessToken()
        let accountID = authStore.loadAccountID()
        let request = try buildRequest(
            body: body,
            token: token,
            accountID: accountID,
            compact: false,
            stream: true,
            sessionID: sessionID
        )
        let bytes = upstream.stream(request)
        guard let override = responseModelOverride, !override.isEmpty else {
            return bytes
        }
        return rewriteStream(bytes, to: override)
    }

    // MARK: - Request Building

    /// Builds the upstream URLRequest. Pulled out of ``sendResponses`` and
    /// ``streamResponses`` so tests can introspect the wire-level headers and
    /// body shape.
    func buildRequest(
        body: [String: Any],
        token: String,
        accountID: String,
        compact: Bool = false,
        stream: Bool,
        sessionID: String? = nil
    ) throws -> URLRequest {
        var forwarded = Self.sanitizeBody(body)
        let upstreamModel = ChatGPTCatalog.upstreamModel(
            for: (body["model"] as? String) ?? ChatGPTCatalog.defaultUpstreamModel
        )
        forwarded["model"] = upstreamModel
        if compact {
            forwarded.removeValue(forKey: "stream")
        } else if stream {
            forwarded["stream"] = true
        }

        let url = compact ? Self.compactURL : Self.responsesURL
        var request = URLRequest(url: url, timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            stream ? "text/event-stream" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("responses=2026-02-06", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        if !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        if let sessionID, !sessionID.isEmpty {
            request.setValue(sessionID, forHTTPHeaderField: "session_id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: forwarded, options: [])
        return request
    }

    // MARK: - Body Sanitisation

    /// Prefix for shim-injected encrypted reasoning blocks. We strip these
    /// before forwarding so we don't send the shim's local ciphertext to the
    /// real ChatGPT backend.
    static let shimEncryptedContentPrefix = "shim-enc:v1:"

    /// Recursively walks the request body and strips any shim-encrypted
    /// reasoning blocks so the upstream payload matches the Responses shape.
    static func sanitizeBody(_ body: [String: Any]) -> [String: Any] {
        guard let output = sanitizeValue(body) as? [String: Any] else {
            return [:]
        }
        return output
    }

    private static func sanitizeValue(_ value: Any) -> Any? {
        if let array = value as? [Any] {
            var out: [Any] = []
            for item in array {
                if let sanitized = sanitizeValue(item) {
                    out.append(sanitized)
                }
            }
            return out
        }
        if let dict = value as? [String: Any] {
            if dict["type"] as? String == "reasoning",
               isShimEncryptedReasoning(dict) {
                return nil
            }
            var out: [String: Any] = [:]
            for (key, nested) in dict {
                if key == "encrypted_content",
                   let raw = nested as? String,
                   raw.hasPrefix(shimEncryptedContentPrefix) {
                    continue
                }
                if let sanitized = sanitizeValue(nested) {
                    out[key] = sanitized
                }
            }
            return out
        }
        return value
    }

    private static func isShimEncryptedReasoning(_ dict: [String: Any]) -> Bool {
        guard let content = dict["encrypted_content"] as? String else { return false }
        return content.hasPrefix(shimEncryptedContentPrefix)
    }

    // MARK: - Model Rewriting

    /// Recursively rewrites `"model": "gpt-5.5"` to the picker-visible slug
    /// so the picker sees the slug it asked for. The Python equivalent only
    /// rewrites when the existing model matches ``CHATGPT_MODEL_SLUG``.
    @discardableResult
    static func rewriteResponseModel(_ payload: Any, to model: String?) -> Any {
        guard let model, !model.isEmpty else { return payload }
        if var dict = payload as? [String: Any] {
            if (dict["model"] as? String) == ChatGPTCatalog.defaultUpstreamModel {
                dict["model"] = model
            }
            for (key, value) in dict {
                dict[key] = rewriteResponseModel(value, to: model)
            }
            return dict
        }
        if let array = payload as? [Any] {
            return array.map { rewriteResponseModel($0, to: model) }
        }
        return payload
    }

    /// Wraps an upstream byte stream so that every `data: <json>` line has
    /// the picker-visible slug re-inserted before being emitted.
    func rewriteStream(
        _ bytes: AsyncThrowingStream<UInt8, Error>,
        to override: String
    ) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var pending: [UInt8] = []
                for try await byte in bytes {
                    pending.append(byte)
                    if byte == UInt8(ascii: "\n") {
                        let line = String(bytes: pending, encoding: .utf8) ?? ""
                        pending.removeAll(keepingCapacity: true)
                        let rewritten = rewriteSSELine(line, to: override)
                        for rewrittenByte in rewritten.utf8 {
                            continuation.yield(UInt8(rewrittenByte))
                        }
                    }
                }
                if !pending.isEmpty {
                    let line = String(bytes: pending, encoding: .utf8) ?? ""
                    let rewritten = rewriteSSELine(line, to: override)
                    for rewrittenByte in rewritten.utf8 {
                        continuation.yield(UInt8(rewrittenByte))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Rewrites a single SSE line so any JSON `model` field gets the override
    /// applied. Non-JSON lines and the `[DONE]` sentinel are passed through.
    private func rewriteSSELine(_ line: String, to override: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return line }
        if trimmed == "data: [DONE]" { return line }
        guard trimmed.hasPrefix("data: ") else { return line }
        let jsonString = String(trimmed.dropFirst("data: ".count))
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return line
        }
        let rewritten = Self.rewriteResponseModel(json, to: override)
        guard let rewrittenData = try? JSONSerialization.data(
            withJSONObject: rewritten,
            options: []
        ), let text = String(data: rewrittenData, encoding: .utf8) else {
            return line
        }
        return "data: \(text)\n"
    }

    // MARK: - Helpers

    private func loadAccessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: authStore.authPath.path) else {
            throw PassthroughError.authFileMissing(authStore.authPath.path)
        }
        guard let data = try? Data(contentsOf: authStore.authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw PassthroughError.authFileMalformed(authStore.authPath.path)
        }
        let tokens = json["tokens"] as? [String: Any]
        let access = (tokens?["access_token"] as? String)
            ?? (json["access_token"] as? String)
            ?? ""
        guard !access.isEmpty else {
            throw PassthroughError.noAccessToken
        }
        return access
    }
}
