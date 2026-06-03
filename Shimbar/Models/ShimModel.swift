import Foundation

// MARK: - ShimModel

/// A configured shim model entry, representing a single model definition
/// from the codex-shim `models.json` configuration file.
///
/// Each `ShimModel` maps a slug (used as an identifier) to a backend
/// provider, base URL, and associated parameters. The struct supports
/// both snake_case JSON (codex-shim format) and Swift camelCase naming.
struct ShimModel: Identifiable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier derived from the slug.
    var id: String { slug }

    /// The model slug used as a unique key (e.g. "claude-sonnet-4").
    let slug: String

    /// The upstream model identifier sent to the provider API.
    let model: String

    /// Human-readable name shown in the UI.
    let displayName: String

    /// The provider backend type: `"openai"`, `"anthropic"`, or
    /// `"generic-chat-completion-api"`.
    let provider: String

    /// The base URL for the provider's API endpoint.
    let baseUrl: String

    /// API key for authentication. May be empty when the key is
    /// stored in the system Keychain instead.
    var apiKey: String = ""

    /// Optional maximum context window size in tokens.
    var maxContextLimit: Int?

    /// Optional maximum output tokens per response.
    var maxOutputTokens: Int?

    /// When `true`, the model does not support image/vision inputs.
    var noImageSupport: Bool = false

    /// Additional HTTP headers to send with every request to this model.
    var extraHeaders: [String: String] = [:]

    // MARK: - Computed Properties

    /// A human-readable name for the provider.
    var providerDisplayName: String {
        switch provider {
        case "openai":
            return "OpenAI"
        case "anthropic":
            return "Anthropic"
        case "generic-chat-completion-api":
            return "Generic Chat API"
        default:
            return provider.capitalized
        }
    }

    /// Whether this model is a ChatGPT passthrough configuration
    /// (uses the special `gpt-5.5` slug with no base URL).
    var isPassthrough: Bool {
        slug == "gpt-5.5" && baseUrl.isEmpty
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case slug
        case model
        case displayName = "display_name"
        case provider
        case baseUrl = "base_url"
        case apiKey = "api_key"
        case maxContextLimit = "max_context_limit"
        case maxOutputTokens = "max_output_tokens"
        case noImageSupport = "no_image_support"
        case extraHeaders = "extra_headers"
    }

    // MARK: - Custom Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? self.model
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.provider = try container.decode(String.self, forKey: .provider)
        self.baseUrl = try container.decode(String.self, forKey: .baseUrl)
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.maxContextLimit = try container.decodeIfPresent(Int.self, forKey: .maxContextLimit)
        self.maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        self.noImageSupport = try container.decodeIfPresent(Bool.self, forKey: .noImageSupport) ?? false
        self.extraHeaders = try container.decodeIfPresent([String: String].self, forKey: .extraHeaders) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(model, forKey: .model)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(provider, forKey: .provider)
        try container.encode(baseUrl, forKey: .baseUrl)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(maxContextLimit, forKey: .maxContextLimit)
        try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encode(noImageSupport, forKey: .noImageSupport)
        try container.encode(extraHeaders, forKey: .extraHeaders)
    }

    // MARK: - Memberwise Initializer

    init(
        slug: String,
        model: String,
        displayName: String,
        provider: String,
        baseUrl: String,
        apiKey: String = "",
        maxContextLimit: Int? = nil,
        maxOutputTokens: Int? = nil,
        noImageSupport: Bool = false,
        extraHeaders: [String: String] = [:]
    ) {
        self.slug = slug
        self.model = model
        self.displayName = displayName
        self.provider = provider
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.maxContextLimit = maxContextLimit
        self.maxOutputTokens = maxOutputTokens
        self.noImageSupport = noImageSupport
        self.extraHeaders = extraHeaders
    }
}

// MARK: - ModelsFile

/// A candidate model entry in the router configuration.
struct RouterCandidate: Codable, Hashable, Identifiable {
    var id: String { slug }

    var slug: String
    var cost: Double
    var supportsImages: Bool
    var card: String

    enum CodingKeys: String, CodingKey {
        case slug
        case cost
        case supportsImages = "supports_images"
        case card
    }
}

/// The router configuration block in `models.json`.
struct RouterConfig: Codable, Hashable {
    var enabled: Bool
    var slug: String
    var displayName: String
    var classifier: String
    var threshold: Double
    var defaultModel: String
    var cache: Bool
    var candidates: [RouterCandidate]

    enum CodingKeys: String, CodingKey {
        case enabled
        case slug
        case displayName = "display_name"
        case classifier
        case threshold
        case defaultModel = "default"
        case cache
        case candidates
    }
}

/// Top-level structure of the codex-shim `models.json` configuration file.
struct ModelsFile: Codable {
    /// The array of configured shim models.
    var models: [ShimModel]
    /// Optional Auto Router configuration.
    var router: RouterConfig?
}
