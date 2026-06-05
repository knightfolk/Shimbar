import XCTest
@testable import Shimbar

final class ChatCompletionModelsTests: XCTestCase {

    // MARK: - Request Encoding

    func testChatCompletionRequestEncoding() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: "system", content: "You are a classifier."),
                ChatMessage(role: "user", content: "Pick the best workflow.")
            ],
            temperature: 0.0,
            maxTokens: 64
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"model\":\"gpt-4o\""))
        XCTAssertTrue(json.contains("\"temperature\":0"))
        XCTAssertTrue(json.contains("\"max_tokens\":64"))
        XCTAssertTrue(json.contains("\"role\":\"system\""))
        XCTAssertTrue(json.contains("\"content\":\"You are a classifier.\""))
    }

    // MARK: - Response Decoding

    func testChatCompletionResponseDecoding() throws {
        let json = """
        {
            "id": "chatcmpl-123",
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
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        XCTAssertEqual(response.id, "chatcmpl-123")
        XCTAssertEqual(response.object, "chat.completion")
        XCTAssertEqual(response.choices.count, 1)
        XCTAssertEqual(response.choices[0].index, 0)
        XCTAssertEqual(response.choices[0].message.role, "assistant")
        XCTAssertEqual(response.choices[0].message.content, "code-review.md")
        XCTAssertEqual(response.choices[0].finishReason, "stop")
    }

    func testChatCompletionResponseMissingFinishReason() throws {
        let json = """
        {
            "id": "chatcmpl-456",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": ""
                    }
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        XCTAssertNil(response.choices[0].finishReason)
        XCTAssertEqual(response.choices[0].message.content, "")
    }

    // MARK: - Round Trip

    func testChatMessageRoundTrip() throws {
        let original = ChatMessage(role: "user", content: "Classify this task")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.content, original.content)
    }
}
