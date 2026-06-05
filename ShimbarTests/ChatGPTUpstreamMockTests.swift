import XCTest
@testable import Shimbar

// MARK: - MockURLProtocol

/// `URLProtocol` subclass that returns canned responses for assertions.
/// Records the last request it handled so tests can introspect URL, headers,
/// and body shape.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    /// A response handler the test registers per URL. Return `nil` to defer
    /// to the next handler; otherwise return a tuple of `(HTTPURLResponse,
    /// Data)` to fulfil the request.
    typealias Handler = (URLRequest) -> (HTTPURLResponse, Data)?

    static let queue = DispatchQueue(label: "com.shimbar.test.mock-url-protocol")
    private static var handlers: [String: Handler] = [:]
    private static var recorded: [URLRequest] = []

    private static var streamChunks: [String: [Data]] = [:]
    private static var streamStatus: [String: Int] = [:]
    private static var streamHeaders: [String: [String: String]] = [:]

    /// Registers a canned JSON response for the given host.
    static func registerJSON(host: String, status: Int = 200, json: [String: Any]) {
        register(host: host) { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = try! JSONSerialization.data(withJSONObject: json, options: [])
            return (response, data)
        }
    }

    /// Registers a handler for the given host.
    static func register(host: String, handler: @escaping Handler) {
        queue.sync { handlers[host] = handler }
    }

    /// Registers a streaming SSE response for the given host.
    static func registerStream(
        host: String,
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "text/event-stream"],
        chunks: [Data]
    ) {
        queue.sync {
            streamStatus[host] = status
            streamHeaders[host] = headers
            streamChunks[host] = chunks
        }
    }

    /// Returns the last recorded request for the given host.
    static func lastRequest(for host: String) -> URLRequest? {
        queue.sync {
            recorded.last { $0.url?.host == host }
        }
    }

    /// Resets all registered handlers and recorded requests.
    static func reset() {
        queue.sync {
            handlers.removeAll()
            recorded.removeAll()
            streamChunks.removeAll()
            streamStatus.removeAll()
            streamHeaders.removeAll()
        }
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.queue.sync {
            Self.recorded.append(self.request)
        }

        if let chunks = Self.queue.sync(execute: { Self.streamChunks[host] }) {
            let status = Self.queue.sync(execute: { Self.streamStatus[host] ?? 200 })
            let headers = Self.queue.sync(execute: { Self.streamHeaders[host] ?? [:] })
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let handler = Self.queue.sync(execute: { Self.handlers[host] })
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        guard let (response, data) = handler(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // Nothing to cancel — startLoading is synchronous in this mock.
    }
}

// MARK: - MockUpstreamClient

/// In-process `UpstreamClient` for tests that need to assert what was sent
/// without going through URLProtocol.
final class MockUpstreamClient: UpstreamClient, @unchecked Sendable {

    struct Call: Equatable {
        var url: String
        var method: String
        var headers: [String: String]
        var body: Data
    }

    enum Response {
        case json([String: Any], status: Int = 200)
        case bytes([UInt8])
        case error(Error)
    }

    private(set) var calls: [Call] = []
    var nextResponse: () -> Response = { .json([:]) }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        switch nextResponse() {
        case let .json(json, status):
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        case .bytes:
            throw URLError(.cannotDecodeContentData)
        case let .error(error):
            throw error
        }
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<UInt8, Error> {
        record(request)
        return AsyncThrowingStream { continuation in
            switch self.nextResponse() {
            case let .bytes(bytes):
                for byte in bytes {
                    continuation.yield(byte)
                }
                continuation.finish()
            case .json:
                continuation.finish(throwing: URLError(.cannotDecodeContentData))
            case let .error(error):
                continuation.finish(throwing: error)
            }
        }
    }

    func synchronousPing(request: URLRequest) -> ChatGPTPassthroughProbe.Status {
        record(request)
        return .available
    }

    private func record(_ request: URLRequest) {
        let headers: [String: String] = (request.allHTTPHeaderFields ?? [:])
            .reduce(into: [:]) { partial, pair in
                partial[pair.key.lowercased()] = pair.value
            }
        let body = request.httpBody ?? Data()
        calls.append(Call(
            url: request.url?.absoluteString ?? "",
            method: request.httpMethod ?? "GET",
            headers: headers,
            body: body
        ))
    }
}

// MARK: - ChatGPTUpstreamMockTests

final class ChatGPTUpstreamMockTests: XCTestCase {

    private var envSnapshot: [String: String] = [:]

    override func setUp() {
        super.setUp()
        envSnapshot = ProcessInfo.processInfo.environment
    }

    override func tearDown() {
        for (key, value) in envSnapshot {
            setenv(key, value, 1)
        }
        MockURLProtocol.reset()
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

    private func makeAuthStore(token: String = "test-token", account: String = "acct-1") throws -> CodexAuthStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-upstream-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(
            at: url,
            json: #"""
            { "tokens": { "access_token": "\#(token)", "account_id": "\#(account)" } }
            """#
        )
        return CodexAuthStore(authPath: url)
    }

    private func mockClient() -> MockUpstreamClient {
        let client = MockUpstreamClient()
        return client
    }

    // MARK: - Request shape (non-streaming)

    func testSendResponsesBuildsCorrectURLMethodAndHeaders() async throws {
        let store = try makeAuthStore(token: "abc-token", account: "acct-xyz")
        let mock = mockClient()
        mock.nextResponse = {
            .json([
                "id": "resp_1",
                "model": ChatGPTCatalog.defaultUpstreamModel,
                "output": [],
            ])
        }

        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        let body: [String: Any] = [
            "model": "gpt-5.4",
            "input": [["type": "text", "text": "hi"]],
            "stream": false,
        ]
        _ = try await upstream.sendResponses(
            body: body,
            responseModelOverride: "gpt-5.4"
        )

        XCTAssertEqual(mock.calls.count, 1)
        let call = mock.calls[0]
        XCTAssertEqual(call.url, ChatGPTUpstream.responsesURL.absoluteString)
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.headers["authorization"], "Bearer abc-token")
        XCTAssertEqual(call.headers["content-type"], "application/json")
        XCTAssertEqual(call.headers["accept"], "application/json")
        XCTAssertEqual(call.headers["openai-beta"], "responses=2026-02-06")
        XCTAssertEqual(call.headers["originator"], "codex_cli_rs")
        XCTAssertEqual(call.headers["chatgpt-account-id"], "acct-xyz")
    }

    func testSendResponsesMapsPickerSlugToUpstreamModel() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        mock.nextResponse = {
            .json([
                "id": "resp_1",
                "model": ChatGPTCatalog.defaultUpstreamModel,
                "output": [],
            ])
        }

        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        _ = try await upstream.sendResponses(
            body: ["model": "openai-gpt-5-5", "input": []],
            responseModelOverride: "openai-gpt-5-5"
        )

        let body = try JSONSerialization.jsonObject(with: mock.calls[0].body) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, ChatGPTCatalog.defaultUpstreamModel)
    }

    func testSendResponsesRewritesResponseModelToOverride() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        mock.nextResponse = {
            .json([
                "id": "resp_1",
                "model": ChatGPTCatalog.defaultUpstreamModel,
                "output": [[
                    "type": "message",
                    "model": ChatGPTCatalog.defaultUpstreamModel,
                    "content": [["type": "output_text", "text": "ok"]],
                ]],
            ])
        }
        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        let result = try await upstream.sendResponses(
            body: ["model": "openai-gpt-5-5", "input": []],
            responseModelOverride: "openai-gpt-5-5"
        )
        XCTAssertEqual(result["model"] as? String, "openai-gpt-5-5")
        let output = result["output"] as? [[String: Any]] ?? []
        XCTAssertEqual(output.first?["model"] as? String, "openai-gpt-5-5")
    }

    func testSendResponsesPreservesNonDefaultModelFields() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        mock.nextResponse = {
            .json([
                "id": "resp_1",
                "model": "gpt-5.4",
                "output": [],
            ])
        }
        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        let result = try await upstream.sendResponses(
            body: ["model": "gpt-5.4", "input": []],
            responseModelOverride: nil
        )
        XCTAssertEqual(result["model"] as? String, "gpt-5.4")
    }

    func testSendResponsesThrowsWhenAuthMissing() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-upstream-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        let store = CodexAuthStore(authPath: url)
        let mock = mockClient()
        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        do {
            _ = try await upstream.sendResponses(
                body: ["model": "gpt-5.5", "input": []]
            )
            XCTFail("Expected an error")
        } catch {
            // expected
        }
        XCTAssertEqual(mock.calls.count, 0)
    }

    func testSendResponsesThrowsWhenAccessTokenMissing() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-upstream-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(at: url, json: #"{ "tokens": { "access_token": "" } }"#)
        let store = CodexAuthStore(authPath: url)
        let mock = mockClient()
        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        do {
            _ = try await upstream.sendResponses(
                body: ["model": "gpt-5.5", "input": []]
            )
            XCTFail("Expected an error")
        } catch {
            // expected
        }
        XCTAssertEqual(mock.calls.count, 0)
    }

    func testSendResponsesSurfacesUpstreamErrors() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        mock.nextResponse = { .json(["error": "boom"], status: 502) }
        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        do {
            _ = try await upstream.sendResponses(
                body: ["model": "gpt-5.5", "input": []]
            )
            XCTFail("Expected an error")
        } catch let ChatGPTUpstream.PassthroughError.upstreamNonSuccess(status, body) {
            XCTAssertEqual(status, 502)
            XCTAssertTrue(body.contains("boom"))
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Body sanitisation

    func testSendResponsesStripsShimEncryptedReasoning() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        mock.nextResponse = { .json(["id": "resp_1", "model": "gpt-5.5"]) }

        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        let body: [String: Any] = [
            "model": "gpt-5.5",
            "input": [[
                "type": "reasoning",
                "encrypted_content": "\(ChatGPTUpstream.shimEncryptedContentPrefix)deadbeef",
            ]],
        ]
        _ = try await upstream.sendResponses(body: body)
        let sentBody = try JSONSerialization.jsonObject(with: mock.calls[0].body) as! [String: Any]
        let input = sentBody["input"] as? [[String: Any]] ?? []
        XCTAssertTrue(input.isEmpty, "Shim-encrypted reasoning block should have been stripped")
    }

    func testSendResponsesPreservesUpstreamReasoning() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        mock.nextResponse = { .json(["id": "resp_1", "model": "gpt-5.5"]) }
        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        let body: [String: Any] = [
            "model": "gpt-5.5",
            "input": [[
                "type": "reasoning",
                "encrypted_content": "raw-ciphertext",
            ]],
        ]
        _ = try await upstream.sendResponses(body: body)
        let sentBody = try JSONSerialization.jsonObject(with: mock.calls[0].body) as! [String: Any]
        let input = sentBody["input"] as? [[String: Any]] ?? []
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input.first?["encrypted_content"] as? String, "raw-ciphertext")
    }

    // MARK: - Compact

    func testSendResponsesCompactStripsStreamFlag() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        mock.nextResponse = { .json(["id": "resp_c"]) }
        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        _ = try await upstream.sendResponses(
            body: ["model": "gpt-5.5", "input": [], "stream": true],
            compact: true
        )
        let body = try JSONSerialization.jsonObject(with: mock.calls[0].body) as! [String: Any]
        XCTAssertNil(body["stream"])
        XCTAssertEqual(mock.calls[0].url, ChatGPTUpstream.compactURL.absoluteString)
    }

    // MARK: - Streaming

    func testStreamResponsesPropagatesBytes() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        let bytes = Array("data: {\"id\":\"r1\",\"model\":\"gpt-5.5\"}\n\ndata: [DONE]\n\n".utf8)
        mock.nextResponse = { .bytes(bytes) }

        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        let stream = try await upstream.streamResponses(
            body: ["model": "gpt-5.5", "input": []],
            responseModelOverride: nil
        )

        var collected = ""
        for try await byte in stream {
            collected.append(Character(UnicodeScalar(byte)))
        }
        XCTAssertEqual(collected, "data: {\"id\":\"r1\",\"model\":\"gpt-5.5\"}\n\ndata: [DONE]\n\n")
    }

    func testStreamResponsesRewritesModelInJSONLines() async throws {
        let store = try makeAuthStore()
        let mock = mockClient()
        let raw = "data: {\"id\":\"r1\",\"model\":\"gpt-5.5\"}\n\ndata: [DONE]\n\n"
        mock.nextResponse = { .bytes(Array(raw.utf8)) }

        let upstream = ChatGPTUpstream(authStore: store, upstream: mock)
        let stream = try await upstream.streamResponses(
            body: ["model": "openai-gpt-5-5", "input": []],
            responseModelOverride: "openai-gpt-5-5"
        )

        var collected = ""
        for try await byte in stream {
            collected.append(Character(UnicodeScalar(byte)))
        }
        XCTAssertTrue(collected.contains("\"model\":\"openai-gpt-5-5\""),
                      "Got: \(collected)")
        XCTAssertTrue(collected.contains("data: [DONE]"))
    }

    // MARK: - URLProtocol integration

    @MainActor
    func testURLProtocolEndToEnd() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt-upstream-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("auth.json")
        try makeAuthFile(
            at: url,
            json: #"{ "tokens": { "access_token": "url-tok", "account_id": "u-acct" } }"#
        )
        let store = CodexAuthStore(authPath: url)

        MockURLProtocol.registerJSON(
            host: "chatgpt.com",
            json: [
                "id": "resp_1",
                "model": ChatGPTCatalog.defaultUpstreamModel,
                "output": [],
            ]
        )

        let live = URLSessionUpstreamClient(session: session)
        let upstream = ChatGPTUpstream(authStore: store, upstream: live)
        let result = try await upstream.sendResponses(
            body: ["model": "openai-gpt-5-5", "input": []],
            responseModelOverride: "openai-gpt-5-5"
        )

        XCTAssertEqual(result["model"] as? String, "openai-gpt-5-5")
        let recorded = MockURLProtocol.lastRequest(for: "chatgpt.com")
        XCTAssertNotNil(recorded)
        XCTAssertEqual(recorded?.url?.host, "chatgpt.com")
        XCTAssertEqual(recorded?.value(forHTTPHeaderField: "Authorization"), "Bearer url-tok")
        XCTAssertEqual(recorded?.value(forHTTPHeaderField: "chatgpt-account-id"), "u-acct")
    }
}
