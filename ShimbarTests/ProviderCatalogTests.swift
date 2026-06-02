import XCTest
@testable import Shimbar

final class ProviderCatalogTests: XCTestCase {

    func testAllProvidersExist() {
        let providers = ProviderCatalog.providers
        XCTAssertFalse(providers.isEmpty, "Provider catalog should not be empty")
        XCTAssertTrue(providers.count >= 14, "Expected at least 14 providers")
    }

    func testProviderLookupById() {
        XCTAssertNotNil(ProviderCatalog.provider(forId: "openai"))
        XCTAssertNotNil(ProviderCatalog.provider(forId: "anthropic"))
        XCTAssertNotNil(ProviderCatalog.provider(forId: "deepseek"))
        XCTAssertNotNil(ProviderCatalog.provider(forId: "gemini"))
        XCTAssertNotNil(ProviderCatalog.provider(forId: "custom"))
        XCTAssertNil(ProviderCatalog.provider(forId: "nonexistent"))
    }

    func testProviderLookupByBaseURL() {
        let openai = ProviderCatalog.provider(forBaseURL: "https://api.openai.com/v1")
        XCTAssertNotNil(openai)
        XCTAssertEqual(openai?.id, "openai")

        let anthropic = ProviderCatalog.provider(forBaseURL: "https://api.anthropic.com/v1")
        XCTAssertNotNil(anthropic)
        XCTAssertEqual(anthropic?.id, "anthropic")

        let withSlash = ProviderCatalog.provider(forBaseURL: "https://api.openai.com/v1/")
        XCTAssertNotNil(withSlash)
        XCTAssertEqual(withSlash?.id, "openai")

        let unknown = ProviderCatalog.provider(forBaseURL: "https://unknown.example.com/api")
        XCTAssertNil(unknown)
    }

    func testProviderIDsAreUnique() {
        let ids = ProviderCatalog.providers.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Provider IDs must be unique")
    }

    func testProviderBaseURLsAreUnique() {
        let urls = ProviderCatalog.providers
            .map(\.defaultBaseURL)
            .filter { !$0.isEmpty }
        let uniqueUrls = Set(urls)
        XCTAssertEqual(urls.count, uniqueUrls.count, "Non-empty provider base URLs must be unique")
    }

    func testProviderDefinitionsHaveRequiredFields() {
        for provider in ProviderCatalog.providers {
            XCTAssertFalse(provider.id.isEmpty, "Provider \(provider) has empty id")
            XCTAssertFalse(provider.name.isEmpty, "Provider \(provider.id) has empty name")
            XCTAssertFalse(provider.icon.isEmpty, "Provider \(provider.id) has empty icon")
            XCTAssertFalse(provider.shimProvider.isEmpty, "Provider \(provider.id) has empty shimProvider")
            XCTAssertFalse(provider.keyValidationPath.isEmpty, "Provider \(provider.id) has empty keyValidationPath")
        }
    }

    func testOpenAIProviderDefinition() {
        guard let openai = ProviderCatalog.provider(forId: "openai") else {
            XCTFail("OpenAI provider should exist")
            return
        }
        XCTAssertEqual(openai.authStyle, .bearer)
        XCTAssertEqual(openai.shimProvider, "openai")
        XCTAssertFalse(openai.models.isEmpty)
    }

    func testAnthropicProviderDefinition() {
        guard let anthropic = ProviderCatalog.provider(forId: "anthropic") else {
            XCTFail("Anthropic provider should exist")
            return
        }
        XCTAssertEqual(anthropic.authStyle, .anthropicHeader)
        XCTAssertEqual(anthropic.shimProvider, "anthropic")
    }

    func testCustomProviderHasEmptyBaseURL() {
        guard let custom = ProviderCatalog.provider(forId: "custom") else {
            XCTFail("Custom provider should exist")
            return
        }
        XCTAssertTrue(custom.defaultBaseURL.isEmpty)
        XCTAssertTrue(custom.models.isEmpty)
    }

    func testProviderModelDefinitions() {
        for provider in ProviderCatalog.providers {
            for model in provider.models {
                XCTAssertFalse(model.modelId.isEmpty, "\(provider.id) has a model with empty modelId")
                XCTAssertFalse(model.displayName.isEmpty, "\(provider.id)/\(model.modelId) has empty displayName")
            }
        }
    }

    func testProviderForBaseURLHandlesTrailingSlashes() {
        let resolved = ProviderCatalog.provider(forBaseURL: "https://api.openai.com/v1///")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.id, "openai")
    }

    func testProviderForBaseURLEmptyString() {
        let resolved = ProviderCatalog.provider(forBaseURL: "")
        XCTAssertNil(resolved)
    }
}
