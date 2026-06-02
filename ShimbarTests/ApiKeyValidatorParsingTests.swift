import XCTest
@testable import Shimbar

final class ApiKeyValidatorParsingTests: XCTestCase {

    func testParseModelIdsFromOpenAIFormat() {
        let json = """
        {
            "data": [
                {"id": "gpt-4o", "object": "model"},
                {"id": "gpt-4o-mini", "object": "model"},
                {"id": "o3", "object": "model"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let ids = ApiKeyValidator.parseModelIds(from: data)
        XCTAssertEqual(ids, ["gpt-4o", "gpt-4o-mini", "o3"])
    }

    func testParseModelIdsFromEmptyData() {
        let json = "{\"data\":[]}"
        let data = json.data(using: .utf8)!
        let ids = ApiKeyValidator.parseModelIds(from: data)
        XCTAssertTrue(ids.isEmpty)
    }

    func testValidationResultCases() {
        let valid = ValidationResult.valid(models: ["gpt-4o", "gpt-4o-mini"])
        if case .valid(let models) = valid {
            XCTAssertEqual(models.count, 2)
        } else {
            XCTFail("Should be valid")
        }

        let invalid = ValidationResult.invalid(reason: "Bad key")
        if case .invalid(let reason) = invalid {
            XCTAssertEqual(reason, "Bad key")
        } else {
            XCTFail("Should be invalid")
        }

        let networkError = ValidationResult.networkError("Timeout")
        if case .networkError(let msg) = networkError {
            XCTAssertEqual(msg, "Timeout")
        } else {
            XCTFail("Should be network error")
        }
    }

    func testParseModelIdsFromModelsArray() {
        let json = """
        {
            "models": [
                {"id": "deepseek-chat"},
                {"id": "deepseek-reasoner"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let ids = ApiKeyValidator.parseModelIds(from: data)
        XCTAssertEqual(ids, ["deepseek-chat", "deepseek-reasoner"])
    }

    func testParseModelIdsFromAnthropicFormatReturnsEmpty() {
        let json = """
        {"id": "msg_123", "content": [{"type": "text", "text": "Hi"}]}
        """
        let data = json.data(using: .utf8)!
        let ids = ApiKeyValidator.parseModelIds(from: data)
        XCTAssertTrue(ids.isEmpty, "Anthropic single-response JSON should return empty model list (key is valid)")
    }

    func testParseModelIdsFromInvalidJSON() {
        let data = "not json at all".data(using: .utf8)!
        let ids = ApiKeyValidator.parseModelIds(from: data)
        XCTAssertTrue(ids.isEmpty)
    }

    func testParseErrorFromProviderResponse() {
        let json = """
        {"error": {"message": "Invalid API key provided", "type": "invalid_request_error"}}
        """
        let data = json.data(using: .utf8)!
        let message = ApiKeyValidator.parseErrorMessage(from: data)
        XCTAssertEqual(message, "Invalid API key provided")
    }

    func testParseErrorStringFormat() {
        let json = "{\"error\": \"Rate limited\"}"
        let data = json.data(using: .utf8)!
        let message = ApiKeyValidator.parseErrorMessage(from: data)
        XCTAssertEqual(message, "Rate limited")
    }

    func testParseErrorMessageFormat() {
        let json = "{\"message\": \"Something went wrong\"}"
        let data = json.data(using: .utf8)!
        let result = ApiKeyValidator.parseErrorMessage(from: data)
        XCTAssertEqual(result, "Something went wrong")
    }

    func testParseErrorMessageReturnsNilForInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        let result = ApiKeyValidator.parseErrorMessage(from: data)
        XCTAssertNil(result)
    }

    func testParseErrorMessageReturnsNilWhenNoKnownKey() {
        let json = "{\"status\": \"ok\", \"count\": 5}"
        let data = json.data(using: .utf8)!
        let result = ApiKeyValidator.parseErrorMessage(from: data)
        XCTAssertNil(result)
    }
}
