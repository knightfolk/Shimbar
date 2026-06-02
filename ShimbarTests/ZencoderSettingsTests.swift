import XCTest
@testable import Shimbar

final class ZencoderSettingsTests: XCTestCase {

    func testDecodeEmptyProviders() throws {
        let json = "{\"providers\":{}}"
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ZencoderSettingsFile.self, from: data)
        XCTAssertTrue(settings.providers.isEmpty)
    }

    func testDecodeWithProviders() throws {
        let json = """
        {
            "providers": {
                "openai": {
                    "mode": "direct",
                    "type": "openai-compatible",
                    "baseUrl": "https://api.openai.com/v1",
                    "apiKey": "sk-test",
                    "models": {
                        "gpt-4o": {
                            "name": "gpt-4o",
                            "displayName": "GPT-4o",
                            "capabilities": [],
                            "options": {
                                "maxOutputTokens": 4096
                            }
                        }
                    }
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ZencoderSettingsFile.self, from: data)

        XCTAssertEqual(settings.providers.count, 1)
        XCTAssertEqual(settings.providers["openai"]?.mode, "direct")
        XCTAssertEqual(settings.providers["openai"]?.baseUrl, "https://api.openai.com/v1")
        XCTAssertEqual(settings.providers["openai"]?.models.count, 1)
        XCTAssertEqual(settings.providers["openai"]?.models["gpt-4o"]?.options?.maxOutputTokens, 4096)
    }

    func testRoundTripEncoding() throws {
        let original = ZencoderSettingsFile(
            providers: [
                "test": ZencoderProvider(
                    mode: "direct",
                    type: "openai-compatible",
                    baseUrl: "https://api.test.com",
                    apiKey: "key123",
                    models: [
                        "model-1": ZencoderModel(
                            name: "model-1",
                            displayName: "Model 1",
                            capabilities: ["chat"],
                            options: ZencoderModelOptions(temperature: 0.7, maxOutputTokens: 2048)
                        )
                    ]
                )
            ],
            mcpServers: [
                "server-1": McpServer(command: "/usr/bin/test", args: ["--flag"], env: ["KEY": "VALUE"])
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ZencoderSettingsFile.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDefaultInitHasNoProviders() {
        let settings = ZencoderSettingsFile()
        XCTAssertTrue(settings.providers.isEmpty)
        XCTAssertNil(settings.mcpServers)
    }

    func testMcpServerEquality() {
        let server1 = McpServer(command: "/usr/bin/test", args: ["--flag"], env: nil)
        let server2 = McpServer(command: "/usr/bin/test", args: ["--flag"], env: nil)
        let server3 = McpServer(command: "/usr/bin/other", args: [], env: nil)

        XCTAssertEqual(server1, server2)
        XCTAssertNotEqual(server1, server3)
    }

    func testDecodeWithMissingOptionalFields() throws {
        let json = """
        {
            "providers": {
                "minimal": {
                    "mode": "direct",
                    "type": "openai-compatible",
                    "baseUrl": "https://api.test.com",
                    "models": {
                        "m1": {
                            "name": "m1",
                            "displayName": "M1"
                        }
                    }
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ZencoderSettingsFile.self, from: data)

        XCTAssertNil(settings.providers["minimal"]?.apiKey)
        let model = settings.providers["minimal"]?.models["m1"]
        XCTAssertEqual(model?.capabilities, [])
        XCTAssertNil(model?.options)
    }
}
