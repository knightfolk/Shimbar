import XCTest
@testable import Shimbar

@MainActor
final class ShimManagerClassifierTests: XCTestCase {

    // MARK: - Mock URLProtocol

    final class MockURLProtocol: URLProtocol {
        typealias Handler = (URLRequest) -> Result

        struct Result {
            var statusCode: Int
            var data: Data
            var headers: [String: String] = ["Content-Type": "application/json"]
            var error: Error?
        }

        static var handler: Handler?
        static var lastRequest: URLRequest?
        static var requestCount: Int = 0

        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requestCount += 1
            Self.lastRequest = request
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: NSError(
                    domain: "MockURLProtocol", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
                return
            }
            let result = handler(request)
            if let error = result.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: result.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: result.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    // MARK: - Fixtures

    private static let validResponseJSON = """
    {
        "id": "chatcmpl-abc",
        "object": "chat.completion",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": "code-review.md"
                },
                "finish_reason": "stop"
            }
        ]
    }
    """

    private var manager: ShimManager!
    private var originalPort: Int!

    override func setUp() {
        super.setUp()
        manager = ShimManager.shared
        originalPort = AppSettings.shared.port
        AppSettings.shared.port = 9876
        MockURLProtocol.requestCount = 0
        MockURLProtocol.lastRequest = nil
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.handler = nil
        AppSettings.shared.port = originalPort
        super.tearDown()
    }

    // MARK: - Happy Path

    func testCallClassifierReturnsContentOn2xx() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: Self.validResponseJSON.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick a workflow", model: "gpt-4o")
        XCTAssertEqual(result, "code-review.md")
    }

    func testCallClassifierTrimsWhitespaceFromContent() async {
        let json = """
        {
            "id": "chatcmpl-xyz",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "  \\n  security-audit.md \\t\\n"
                    },
                    "finish_reason": "stop"
                }
            ]
        }
        """
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: json.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertEqual(result, "security-audit.md")
    }

    func testCallClassifierAccepts201Created() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 201,
                data: Self.validResponseJSON.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertEqual(result, "code-review.md")
    }

    func testCallClassifierAccepts299UpperBound() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 299,
                data: Self.validResponseJSON.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertEqual(result, "code-review.md")
    }

    func testCallClassifierReturnsFirstChoiceWhenMultiple() async {
        let json = """
        {
            "id": "chatcmpl-multi",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "first-choice.md"},
                    "finish_reason": "stop"
                },
                {
                    "index": 1,
                    "message": {"role": "assistant", "content": "second-choice.md"},
                    "finish_reason": "stop"
                }
            ]
        }
        """
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: json.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertEqual(result, "first-choice.md")
    }

    func testCallClassifierReturnsEmptyStringForEmptyContent() async {
        let json = """
        {
            "id": "chatcmpl-empty",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": ""},
                    "finish_reason": "stop"
                }
            ]
        }
        """
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: json.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertEqual(result, "")
    }

    // MARK: - Non-2xx

    func testCallClassifierReturnsNilOn400() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 400,
                data: Data("bad request".utf8)
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    func testCallClassifierReturnsNilOn404() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 404,
                data: Data("not found".utf8)
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    func testCallClassifierReturnsNilOn500() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 500,
                data: Data("server error".utf8)
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    func testCallClassifierReturnsNilOn199BelowRange() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 199,
                data: Self.validResponseJSON.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    func testCallClassifierReturnsNilOn300AboveRange() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 300,
                data: Self.validResponseJSON.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    // MARK: - Network Errors

    func testCallClassifierReturnsNilOnConnectionError() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 0,
                data: Data(),
                error: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorCannotConnectToHost,
                    userInfo: [NSLocalizedDescriptionKey: "Connection refused"]
                )
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    func testCallClassifierReturnsNilOnTimeout() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 0,
                data: Data(),
                error: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorTimedOut,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out"]
                )
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    // MARK: - Malformed Responses

    func testCallClassifierReturnsNilOnInvalidJSON() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: Data("not valid json {".utf8)
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    func testCallClassifierReturnsNilOnMissingChoices() async {
        let json = """
        {
            "id": "chatcmpl-no-choices",
            "object": "chat.completion"
        }
        """
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: json.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    func testCallClassifierReturnsNilOnEmptyChoices() async {
        let json = """
        {
            "id": "chatcmpl-empty-choices",
            "object": "chat.completion",
            "choices": []
        }
        """
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: json.data(using: .utf8)!
            )
        }

        let result = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")
        XCTAssertNil(result)
    }

    // MARK: - Request Shape

    func testCallClassifierSendsPOSTToChatCompletions() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: Self.validResponseJSON.data(using: .utf8)!
            )
        }

        _ = await manager.callClassifier(prompt: "Pick a workflow", model: "gpt-4o")

        guard let request = MockURLProtocol.lastRequest else {
            XCTFail("No request was made")
            return
        }
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.scheme, "http")
        XCTAssertEqual(request.url?.host, "127.0.0.1")
        XCTAssertEqual(request.url?.port, 9876)
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testCallClassifierEncodesPromptAsUserMessage() async throws {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: Self.validResponseJSON.data(using: .utf8)!
            )
        }

        let prompt = "Classify this task carefully"
        _ = await manager.callClassifier(prompt: prompt, model: "claude-sonnet-4")

        guard let request = MockURLProtocol.lastRequest else {
            XCTFail("No request was made")
            return
        }
        guard let body = Self.requestBodyData(from: request) else {
            XCTFail("Request body missing")
            return
        }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "claude-sonnet-4")
        XCTAssertEqual(json?["temperature"] as? Double, 0.0)
        XCTAssertEqual(json?["max_tokens"] as? Int, 64)

        let messages = json?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
        XCTAssertEqual(messages?.first?["content"] as? String, prompt)
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        var data = Data()
        stream.open()
        defer { stream.close() }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    func testCallClassifierHonorsConfiguredPort() async {
        AppSettings.shared.port = 12345
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: Self.validResponseJSON.data(using: .utf8)!
            )
        }

        _ = await manager.callClassifier(prompt: "Pick", model: "gpt-4o")

        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.port, 12345)
    }
}
