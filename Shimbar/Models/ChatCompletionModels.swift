import Foundation

// MARK: - Chat Completion Request / Response

/// OpenAI-compatible chat completion request body.
struct ChatCompletionRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double?
    var maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

/// A single message in a chat completion conversation.
struct ChatMessage: Codable {
    var role: String
    var content: String
}

/// OpenAI-compatible chat completion response body.
struct ChatCompletionResponse: Codable {
    var id: String
    var object: String
    var choices: [ChatChoice]
}

/// A single choice in a chat completion response.
struct ChatChoice: Codable {
    var index: Int
    var message: ChatMessage
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}
