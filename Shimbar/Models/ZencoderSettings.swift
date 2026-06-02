import Foundation

struct ZencoderSettingsFile: Codable, Equatable {
    var providers: [String: ZencoderProvider]
    var mcpServers: [String: McpServer]?
    
    init(providers: [String: ZencoderProvider] = [:], mcpServers: [String: McpServer]? = nil) {
        self.providers = providers
        self.mcpServers = mcpServers
    }
}

struct McpServer: Codable, Equatable {
    var command: String
    var args: [String]?
    var env: [String: String]?
}

struct ZencoderProvider: Codable, Equatable {
    var mode: String
    var type: String
    var baseUrl: String
    var apiKey: String?
    var models: [String: ZencoderModel]
    
    init(mode: String = "direct", type: String = "openai-compatible", baseUrl: String, apiKey: String?, models: [String: ZencoderModel] = [:]) {
        self.mode = mode
        self.type = type
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.models = models
    }
}

struct ZencoderModel: Codable, Equatable {
    var name: String
    var displayName: String
    var capabilities: [String]
    var options: ZencoderModelOptions?
    
    init(name: String, displayName: String, capabilities: [String] = [], options: ZencoderModelOptions? = nil) {
        self.name = name
        self.displayName = displayName
        self.capabilities = capabilities
        self.options = options
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        self.options = try container.decodeIfPresent(ZencoderModelOptions.self, forKey: .options)
    }
}

struct ZencoderModelOptions: Codable, Equatable {
    var temperature: Double?
    var maxOutputTokens: Int?
}
