import XCTest
@testable import Shimbar

final class ShimModelTests: XCTestCase {

    private let exampleJSON: [String: Any] = [
        "slug": "gpt-4o",
        "model": "gpt-4o",
        "display_name": "OpenAI GPT-4o",
        "provider": "openai",
        "base_url": "https://api.openai.com/v1",
        "api_key": "sk-test-key",
        "max_context_limit": 128000,
        "max_output_tokens": 4096,
        "no_image_support": false,
        "extra_headers": ["X-Custom": "value"]
    ]

    func testDecodeShimModelFromJSON() throws {
        let data = try JSONSerialization.data(withJSONObject: exampleJSON)
        let model = try JSONDecoder().decode(ShimModel.self, from: data)

        XCTAssertEqual(model.slug, "gpt-4o")
        XCTAssertEqual(model.model, "gpt-4o")
        XCTAssertEqual(model.displayName, "OpenAI GPT-4o")
        XCTAssertEqual(model.provider, "openai")
        XCTAssertEqual(model.baseUrl, "https://api.openai.com/v1")
        XCTAssertEqual(model.apiKey, "sk-test-key")
        XCTAssertEqual(model.maxContextLimit, 128000)
        XCTAssertEqual(model.maxOutputTokens, 4096)
        XCTAssertFalse(model.noImageSupport)
        XCTAssertEqual(model.extraHeaders["X-Custom"], "value")
    }

    func testDecodeShimModelWithMissingOptionalFields() throws {
        var minimal = exampleJSON
        minimal.removeValue(forKey: "api_key")
        minimal.removeValue(forKey: "max_context_limit")
        minimal.removeValue(forKey: "max_output_tokens")
        minimal.removeValue(forKey: "no_image_support")
        minimal.removeValue(forKey: "extra_headers")
        minimal.removeValue(forKey: "slug")

        let data = try JSONSerialization.data(withJSONObject: minimal)
        let model = try JSONDecoder().decode(ShimModel.self, from: data)

        XCTAssertEqual(model.slug, model.model)
        XCTAssertEqual(model.apiKey, "")
        XCTAssertNil(model.maxContextLimit)
        XCTAssertNil(model.maxOutputTokens)
        XCTAssertFalse(model.noImageSupport)
        XCTAssertTrue(model.extraHeaders.isEmpty)
    }

    func testDecodeShimModelFailsWithMissingRequiredFields() {
        let requiredKeys = ["model", "display_name", "provider", "base_url"]
        for key in requiredKeys {
            var incomplete = exampleJSON
            incomplete.removeValue(forKey: key)
            let data = try! JSONSerialization.data(withJSONObject: incomplete)
            XCTAssertThrowsError(try JSONDecoder().decode(ShimModel.self, from: data))
        }
    }

    func testEncodeShimModelRoundTrip() throws {
        let original = ShimModel(
            slug: "test-slug",
            model: "test-model",
            displayName: "Test Model",
            provider: "openai",
            baseUrl: "https://api.test.com/v1",
            apiKey: "sk-test",
            maxContextLimit: 64000,
            maxOutputTokens: 2048,
            noImageSupport: true,
            extraHeaders: ["X-Test": "yes"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ShimModel.self, from: data)

        XCTAssertEqual(original.slug, decoded.slug)
        XCTAssertEqual(original.model, decoded.model)
        XCTAssertEqual(original.displayName, decoded.displayName)
        XCTAssertEqual(original.provider, decoded.provider)
        XCTAssertEqual(original.baseUrl, decoded.baseUrl)
        XCTAssertEqual(original.apiKey, decoded.apiKey)
        XCTAssertEqual(original.maxContextLimit, decoded.maxContextLimit)
        XCTAssertEqual(original.maxOutputTokens, decoded.maxOutputTokens)
        XCTAssertEqual(original.noImageSupport, decoded.noImageSupport)
        XCTAssertEqual(original.extraHeaders, decoded.extraHeaders)
    }

    func testIdReturnsSlug() {
        let model = ShimModel(slug: "my-slug", model: "my-model", displayName: "Test", provider: "openai", baseUrl: "https://api.test.com")
        XCTAssertEqual(model.id, "my-slug")
    }

    func testProviderDisplayNameMappings() {
        let openai = ShimModel(slug: "a", model: "a", displayName: "", provider: "openai", baseUrl: "")
        XCTAssertEqual(openai.providerDisplayName, "OpenAI")

        let anthropic = ShimModel(slug: "b", model: "b", displayName: "", provider: "anthropic", baseUrl: "")
        XCTAssertEqual(anthropic.providerDisplayName, "Anthropic")

        let generic = ShimModel(slug: "c", model: "c", displayName: "", provider: "generic-chat-completion-api", baseUrl: "")
        XCTAssertEqual(generic.providerDisplayName, "Generic Chat API")

        let unknown = ShimModel(slug: "d", model: "d", displayName: "", provider: "custom-provider", baseUrl: "")
        XCTAssertEqual(unknown.providerDisplayName, "Custom-Provider")
    }

    func testIsPassthrough() {
        let passthrough = ShimModel(slug: "gpt-5.5", model: "gpt-5.5", displayName: "ChatGPT", provider: "openai", baseUrl: "")
        XCTAssertTrue(passthrough.isPassthrough)

        let notPassthrough = ShimModel(slug: "gpt-5.5", model: "gpt-5.5", displayName: "ChatGPT", provider: "openai", baseUrl: "https://api.openai.com")
        XCTAssertFalse(notPassthrough.isPassthrough)

        let otherSlug = ShimModel(slug: "other", model: "other", displayName: "", provider: "openai", baseUrl: "")
        XCTAssertFalse(otherSlug.isPassthrough)
    }

    func testHashableAndEquatable() {
        let model1 = ShimModel(slug: "test", model: "test", displayName: "Test", provider: "openai", baseUrl: "https://api.test.com")
        let model2 = ShimModel(slug: "test", model: "test", displayName: "Test", provider: "openai", baseUrl: "https://api.test.com")
        let model3 = ShimModel(slug: "other", model: "other", displayName: "Other", provider: "openai", baseUrl: "https://api.test.com")

        XCTAssertEqual(model1, model2)
        XCTAssertNotEqual(model1, model3)
        XCTAssertEqual(model1.hashValue, model2.hashValue)
    }

    func testDecodeEmptyStringApiKey() throws {
        var json = exampleJSON
        json["api_key"] = ""
        let data = try JSONSerialization.data(withJSONObject: json)
        let model = try JSONDecoder().decode(ShimModel.self, from: data)
        XCTAssertEqual(model.apiKey, "")
    }

    func testDecodeNullApiKey() throws {
        var json = exampleJSON
        json["api_key"] = NSNull()
        let data = try JSONSerialization.data(withJSONObject: json)
        let model = try JSONDecoder().decode(ShimModel.self, from: data)
        XCTAssertEqual(model.apiKey, "")
    }
}
