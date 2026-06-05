import Foundation

// MARK: - ChatGPTPassthroughProbe

/// Quick availability check for the ChatGPT passthrough. Used by the picker
/// UI, the `GET /health` endpoint, and the request router to decide whether
/// to advertise ChatGPT slugs in the first place.
///
/// Mirrors the Python ``chatgpt_passthrough_available`` semantics:
///   1. `CODEX_SHIM_DISABLE_CHATGPT` env var short-circuits to `false`.
///   2. The auth file must exist, parse as JSON, hold a `tokens` object, and
///      a non-empty `access_token`.
///   3. Optionally, a cheap upstream ping confirms the token is still valid.
struct ChatGPTPassthroughProbe: Sendable {

    /// What the probe found. Useful for surfacing in the picker UI.
    enum Status: Equatable, Sendable {
        case available
        case disabledByEnv
        case missingAuthFile
        case malformedAuth
        case missingAccessToken
        case pingFailed(reason: String)
    }

    let authStore: CodexAuthStore
    let upstream: UpstreamClient
    let pingEnabled: Bool

    init(
        authStore: CodexAuthStore = CodexAuthStore(),
        upstream: UpstreamClient = URLSessionUpstreamClient.shared,
        pingEnabled: Bool = true
    ) {
        self.authStore = authStore
        self.upstream = upstream
        self.pingEnabled = pingEnabled
    }

    /// Returns the raw ``Status`` of the passthrough.
    /// - Returns: A ``Status`` describing why the passthrough is (un)available.
    func status() -> Status {
        if Self.isDisabledByEnv {
            return .disabledByEnv
        }
        if !FileManager.default.fileExists(atPath: authStore.authPath.path) {
            return .missingAuthFile
        }
        let data: Data
        do {
            data = try Data(contentsOf: authStore.authPath)
        } catch {
            return .malformedAuth
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformedAuth
        }
        guard let tokens = json["tokens"] as? [String: Any] else {
            return .missingAccessToken
        }
        guard let access = tokens["access_token"] as? String, !access.isEmpty else {
            return .missingAccessToken
        }
        if pingEnabled {
            switch pingStatus(token: access) {
            case .available:
                return .available
            case let .pingFailed(reason):
                return .pingFailed(reason: reason)
            case .disabledByEnv, .missingAuthFile, .malformedAuth, .missingAccessToken:
                return .available
            }
        }
        return .available
    }

    /// Returns `true` when the passthrough is currently usable. Convenience
    /// wrapper around ``status()`` that ignores the failure-reason for the
    /// "no" cases.
    func isAvailable() -> Bool {
        switch status() {
        case .available: return true
        case .disabledByEnv, .missingAuthFile, .malformedAuth,
             .missingAccessToken, .pingFailed:
            return false
        }
    }

    /// Backwards-compatible free function — see ``isAvailable()``.
    func available() -> Bool { isAvailable() }

    // MARK: - Env

    /// Returns `true` when `CODEX_SHIM_DISABLE_CHATGPT` is set to a truthy
    /// value (`1`, `true`, `yes`, `on`).
    static var isDisabledByEnv: Bool {
        guard let raw = ProcessInfo.processInfo.environment["CODEX_SHIM_DISABLE_CHATGPT"] else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(raw.lowercased())
    }

    // MARK: - Cheap Upstream Ping

    private func pingStatus(token: String) -> Status {
        guard let url = URL(string: "https://chatgpt.com/backend-api/codex/ping") else {
            return .available
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("responses=2026-02-06", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        return upstream.synchronousPing(request: request)
    }
}

// MARK: - UpstreamClient

/// Lightweight HTTP client abstraction used by the ChatGPT passthrough.
///
/// Production code uses ``URLSessionUpstreamClient/shared``; tests inject a
/// mock that swaps in a custom `URLProtocol` so requests can be intercepted
/// without touching the network.
protocol UpstreamClient: Sendable {
    /// Sends a request and returns the response payload + status.
    /// - Parameter request: The URL request to send.
    /// - Returns: Tuple of response data and the HTTPURLResponse.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Streams the response body as raw bytes.
    /// - Parameter request: The URL request to send.
    /// - Returns: An `AsyncThrowingStream` of byte chunks.
    func stream(_ request: URLRequest) -> AsyncThrowingStream<UInt8, Error>

    /// Synchronous probe used by ``ChatGPTPassthroughProbe`` so tests can
    /// avoid bridging `async` into synchronous XCTest assertions.
    /// - Parameter request: The URL request to send.
    /// - Returns: The probe status. `.available` for any 2xx/3xx; failure
    ///   reason otherwise.
    func synchronousPing(request: URLRequest) -> ChatGPTPassthroughProbe.Status
}

// MARK: - URLSessionUpstreamClient

/// Default `URLSession`-backed ``UpstreamClient``. Used in production.
final class URLSessionUpstreamClient: UpstreamClient, @unchecked Sendable {

    static let shared = URLSessionUpstreamClient()

    private let session: URLSession
    private let syncSession: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.syncSession = URLSession(configuration: config)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode)
                    else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: URLError(.badServerResponse))
                        DebugLogger.log("URLSessionUpstreamClient: stream bad status \(status)")
                        return
                    }
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        continuation.yield(byte)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func synchronousPing(request: URLRequest) -> ChatGPTPassthroughProbe.Status {
        let semaphore = DispatchSemaphore(value: 0)
        var output: ChatGPTPassthroughProbe.Status = .available
        let task = syncSession.dataTask(with: request) { _, response, error in
            if let error {
                output = .pingFailed(reason: error.localizedDescription)
            } else if let http = response as? HTTPURLResponse {
                if (200..<400).contains(http.statusCode) {
                    output = .available
                } else {
                    output = .pingFailed(reason: "status \(http.statusCode)")
                }
            } else {
                output = .pingFailed(reason: "no response")
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return output
    }
}
