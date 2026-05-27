// MARK: - ApiKeyValidator.swift
// Shimbar – Async API key validation against provider endpoints
// macOS 14+

import Foundation

// MARK: - Validation Result

/// Outcome of an API key validation attempt.
enum ValidationResult: Sendable {
    /// The key was accepted. Includes model IDs returned by the provider.
    case valid(models: [String])
    /// The provider explicitly rejected the key (401 / 403).
    case invalid(reason: String)
    /// The validation endpoint could not be reached.
    case networkError(String)
}

// MARK: - API Key Validator

/// Tests an API key by hitting the provider's validation endpoint.
struct ApiKeyValidator: Sendable {

    /// Default request timeout in seconds.
    private static let timeoutInterval: TimeInterval = 10

    // MARK: Public API

    /// Validate `key` against the given `provider`.
    ///
    /// - Parameters:
    ///   - key: The raw API key string.
    ///   - provider: The provider definition describing endpoints and auth style.
    /// - Returns: A ``ValidationResult`` indicating success, rejection, or network failure.
    static func validate(key: String, provider: ProviderDefinition) async -> ValidationResult {
        do {
            let request = try buildRequest(key: key, provider: provider)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError("Unexpected response type")
            }

            switch httpResponse.statusCode {
            case 200:
                let modelIds = parseModelIds(from: data)
                return .valid(models: modelIds)

            case 401, 403:
                let reason = parseErrorMessage(from: data)
                    ?? "Authentication failed (HTTP \(httpResponse.statusCode))"
                return .invalid(reason: reason)

            default:
                let reason = parseErrorMessage(from: data)
                    ?? "Unexpected status code: \(httpResponse.statusCode)"
                return .invalid(reason: reason)
            }
        } catch let error as URLError {
            return .networkError(error.localizedDescription)
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Request Building

    private static func buildRequest(
        key: String,
        provider: ProviderDefinition
    ) throws -> URLRequest {
        switch provider.authStyle {
        case .bearer:
            return try buildBearerRequest(key: key, provider: provider)
        case .anthropicHeader:
            return try buildAnthropicRequest(key: key, provider: provider)
        case .queryParam:
            return try buildQueryParamRequest(key: key, provider: provider)
        }
    }

    /// Standard `Authorization: Bearer <key>` GET request.
    private static func buildBearerRequest(
        key: String,
        provider: ProviderDefinition
    ) throws -> URLRequest {
        let urlString = provider.defaultBaseURL + provider.keyValidationPath
        guard let url = URL(string: urlString) else {
            throw ValidationError.invalidURL(urlString)
        }

        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Anthropic-style POST with `x-api-key` header and a minimal message body.
    private static func buildAnthropicRequest(
        key: String,
        provider: ProviderDefinition
    ) throws -> URLRequest {
        let urlString = provider.defaultBaseURL + provider.keyValidationPath
        guard let url = URL(string: urlString) else {
            throw ValidationError.invalidURL(urlString)
        }

        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Minimal body to trigger authentication without real usage.
        let body: [String: Any] = [
            "model": "claude-haiku-3-5-20241022",
            "max_tokens": 1,
            "messages": [
                ["role": "user", "content": "hi"]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Query-parameter auth: `?key=<key>`.
    private static func buildQueryParamRequest(
        key: String,
        provider: ProviderDefinition
    ) throws -> URLRequest {
        let urlString = provider.defaultBaseURL + provider.keyValidationPath
        guard var components = URLComponents(string: urlString) else {
            throw ValidationError.invalidURL(urlString)
        }

        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "key", value: key))
        components.queryItems = items

        guard let url = components.url else {
            throw ValidationError.invalidURL(urlString)
        }

        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Response Parsing

    /// Extracts model ID strings from a typical `{ "data": [ { "id": "..." }, ... ] }` response.
    private static func parseModelIds(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Standard OpenAI-compatible format
        if let dataArray = json["data"] as? [[String: Any]] {
            return dataArray.compactMap { $0["id"] as? String }
        }

        // Anthropic returns a single response object — key is valid if we got 200.
        if json["id"] != nil || json["content"] != nil {
            return []
        }

        // Some providers return a top-level array under "models"
        if let modelsArray = json["models"] as? [[String: Any]] {
            return modelsArray.compactMap { $0["id"] as? String }
        }

        return []
    }

    /// Attempts to extract a human-readable error message from the response body.
    private static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // { "error": { "message": "..." } }
        if let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String
        {
            return message
        }

        // { "error": "some string" }
        if let errorString = json["error"] as? String {
            return errorString
        }

        // { "message": "..." }
        if let message = json["message"] as? String {
            return message
        }

        return nil
    }

    // MARK: - Errors

    private enum ValidationError: LocalizedError {
        case invalidURL(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                return "Invalid validation URL: \(url)"
            }
        }
    }
}
