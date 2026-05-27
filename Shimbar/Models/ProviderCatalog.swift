// MARK: - ProviderCatalog.swift
// Shimbar – Built-in catalog of AI model providers
// macOS 14+

import Foundation

// MARK: - Provider Definition

/// Describes a known AI model provider, including connection details and available models.
struct ProviderDefinition: Identifiable, Sendable {

    let id: String                    // e.g. "openai"
    let name: String                  // e.g. "OpenAI"
    let icon: String                  // SF Symbol name
    let shimProvider: String          // codex-shim provider value
    let defaultBaseURL: String
    let keyPlaceholder: String        // e.g. "sk-..."
    let keyValidationPath: String     // e.g. "/models"
    let docsURL: URL                  // Link to obtain an API key
    let models: [ProviderModelDef]
    let authStyle: AuthStyle

    /// How the provider expects the API key to be transmitted.
    enum AuthStyle: Sendable {
        /// `Authorization: Bearer <key>`
        case bearer
        /// `x-api-key: <key>` (Anthropic-specific)
        case anthropicHeader
        /// `?key=<key>` query parameter
        case queryParam
    }
}

// MARK: - Provider Model Definition

/// A single model offered by a provider.
struct ProviderModelDef: Identifiable, Sendable {
    var id: String { modelId }

    let modelId: String
    let displayName: String
    let maxContextLimit: Int?
    let maxOutputTokens: Int?
    let supportsImages: Bool
    let isRecommended: Bool
}

// MARK: - Provider Catalog

/// Static catalog of all known providers and their models.
struct ProviderCatalog {

    // MARK: All Providers

    static let providers: [ProviderDefinition] = [
        openAI,
        anthropic,
        deepSeek,
        gemini,
        zhipu,
        miniMax,
        qwen,
        moonshot,
        openRouter,
        together,
        fireworks,
        omlx,
        opencodeGo,
        custom,
    ]

    // MARK: Lookup

    /// Returns the provider definition matching the given identifier, if any.
    static func provider(forId id: String) -> ProviderDefinition? {
        providers.first { $0.id == id }
    }

    /// Best-effort match of a base URL to a known provider.
    static func provider(forBaseURL baseURL: String) -> ProviderDefinition? {
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return providers.first {
            !$0.defaultBaseURL.isEmpty &&
            normalized.hasPrefix($0.defaultBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
    }

    // MARK: - Individual Provider Definitions

    // 1. OpenAI
    private static let openAI = ProviderDefinition(
        id: "openai",
        name: "OpenAI",
        icon: "brain.head.profile",
        shimProvider: "openai",
        defaultBaseURL: "https://api.openai.com/v1",
        keyPlaceholder: "sk-...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://platform.openai.com/api-keys")!,
        models: [
            ProviderModelDef(
                modelId: "gpt-5.5",
                displayName: "GPT-5.5",
                maxContextLimit: 400_000,
                maxOutputTokens: 32_768,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "gpt-4.1",
                displayName: "GPT-4.1",
                maxContextLimit: 1_000_000,
                maxOutputTokens: 32_768,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "gpt-4.1-mini",
                displayName: "GPT-4.1 mini",
                maxContextLimit: 1_000_000,
                maxOutputTokens: 16_384,
                supportsImages: true,
                isRecommended: false
            ),
            ProviderModelDef(
                modelId: "o3",
                displayName: "o3",
                maxContextLimit: 200_000,
                maxOutputTokens: 100_000,
                supportsImages: true,
                isRecommended: false
            ),
            ProviderModelDef(
                modelId: "o4-mini",
                displayName: "o4-mini",
                maxContextLimit: 200_000,
                maxOutputTokens: 100_000,
                supportsImages: true,
                isRecommended: false
            ),
        ],
        authStyle: .bearer
    )

    // 2. Anthropic
    private static let anthropic = ProviderDefinition(
        id: "anthropic",
        name: "Anthropic",
        icon: "sparkles",
        shimProvider: "anthropic",
        defaultBaseURL: "https://api.anthropic.com/v1",
        keyPlaceholder: "sk-ant-...",
        keyValidationPath: "/messages",
        docsURL: URL(string: "https://console.anthropic.com/settings/keys")!,
        models: [
            ProviderModelDef(
                modelId: "claude-opus-4-20250514",
                displayName: "Claude Opus 4",
                maxContextLimit: 200_000,
                maxOutputTokens: 32_768,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "claude-sonnet-4-20250514",
                displayName: "Claude Sonnet 4",
                maxContextLimit: 200_000,
                maxOutputTokens: 16_384,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "claude-haiku-3-5-20241022",
                displayName: "Claude Haiku 3.5",
                maxContextLimit: 200_000,
                maxOutputTokens: 8_192,
                supportsImages: true,
                isRecommended: false
            ),
        ],
        authStyle: .anthropicHeader
    )

    // 3. DeepSeek
    private static let deepSeek = ProviderDefinition(
        id: "deepseek",
        name: "DeepSeek",
        icon: "magnifyingglass.circle",
        shimProvider: "openai",
        defaultBaseURL: "https://api.deepseek.com/v1",
        keyPlaceholder: "sk-...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://platform.deepseek.com/api_keys")!,
        models: [
            ProviderModelDef(
                modelId: "deepseek-chat",
                displayName: "DeepSeek V3",
                maxContextLimit: 128_000,
                maxOutputTokens: 8_192,
                supportsImages: false,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "deepseek-reasoner",
                displayName: "DeepSeek R1",
                maxContextLimit: 128_000,
                maxOutputTokens: 8_192,
                supportsImages: false,
                isRecommended: true
            ),
        ],
        authStyle: .bearer
    )

    // 4. Google Gemini
    private static let gemini = ProviderDefinition(
        id: "gemini",
        name: "Google Gemini",
        icon: "diamond",
        shimProvider: "openai",
        defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
        keyPlaceholder: "AIza...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://aistudio.google.com/apikey")!,
        models: [
            ProviderModelDef(
                modelId: "gemini-2.5-pro",
                displayName: "Gemini 2.5 Pro",
                maxContextLimit: 1_000_000,
                maxOutputTokens: 65_536,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "gemini-2.5-flash",
                displayName: "Gemini 2.5 Flash",
                maxContextLimit: 1_000_000,
                maxOutputTokens: 65_536,
                supportsImages: true,
                isRecommended: false
            ),
        ],
        authStyle: .bearer
    )

    // 5. Z.AI (Zhipu)
    private static let zhipu = ProviderDefinition(
        id: "zhipu",
        name: "Z.AI (Zhipu)",
        icon: "flame",
        shimProvider: "openai",
        defaultBaseURL: "https://api.z.ai/api/coding/paas/v4",
        keyPlaceholder: "Bearer token...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://z.ai")!,
        models: [
            ProviderModelDef(
                modelId: "glm-5.1",
                displayName: "GLM-5.1",
                maxContextLimit: 128_000,
                maxOutputTokens: 16_384,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "glm-4.7",
                displayName: "GLM-4.7",
                maxContextLimit: 128_000,
                maxOutputTokens: 16_384,
                supportsImages: true,
                isRecommended: false
            ),
            ProviderModelDef(
                modelId: "glm-4.6",
                displayName: "GLM-4.6",
                maxContextLimit: 128_000,
                maxOutputTokens: 16_384,
                supportsImages: false,
                isRecommended: false
            ),
        ],
        authStyle: .bearer
    )

    // 6. MiniMax
    private static let miniMax = ProviderDefinition(
        id: "minimax",
        name: "MiniMax",
        icon: "bolt.circle",
        shimProvider: "openai",
        defaultBaseURL: "https://api.minimax.io/v1",
        keyPlaceholder: "Bearer token...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://www.minimax.io")!,
        models: [
            ProviderModelDef(
                modelId: "MiniMax-M2.7",
                displayName: "MiniMax M2.7",
                maxContextLimit: 1_000_000,
                maxOutputTokens: 32_768,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "MiniMax-M2.5",
                displayName: "MiniMax M2.5",
                maxContextLimit: 1_000_000,
                maxOutputTokens: 32_768,
                supportsImages: true,
                isRecommended: false
            ),
            ProviderModelDef(
                modelId: "MiniMax-M2.1",
                displayName: "MiniMax M2.1",
                maxContextLimit: 1_000_000,
                maxOutputTokens: 16_384,
                supportsImages: false,
                isRecommended: false
            ),
        ],
        authStyle: .bearer
    )

    // 7. Qwen (Alibaba)
    private static let qwen = ProviderDefinition(
        id: "qwen",
        name: "Qwen (Alibaba)",
        icon: "cloud",
        shimProvider: "openai",
        defaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        keyPlaceholder: "sk-...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://dashscope.console.aliyun.com/")!,
        models: [
            ProviderModelDef(
                modelId: "qwen3-coder",
                displayName: "Qwen3 Coder",
                maxContextLimit: 131_072,
                maxOutputTokens: 16_384,
                supportsImages: false,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "qwen3-235b-a22b",
                displayName: "Qwen3 235B",
                maxContextLimit: 131_072,
                maxOutputTokens: 16_384,
                supportsImages: false,
                isRecommended: false
            ),
            ProviderModelDef(
                modelId: "qwen3-32b",
                displayName: "Qwen3 32B",
                maxContextLimit: 131_072,
                maxOutputTokens: 16_384,
                supportsImages: false,
                isRecommended: false
            ),
        ],
        authStyle: .bearer
    )

    // 8. Moonshot (Kimi)
    private static let moonshot = ProviderDefinition(
        id: "moonshot",
        name: "Moonshot (Kimi)",
        icon: "moon.stars",
        shimProvider: "openai",
        defaultBaseURL: "https://api.moonshot.ai/v1",
        keyPlaceholder: "Bearer token...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://platform.moonshot.ai")!,
        models: [
            ProviderModelDef(
                modelId: "kimi-k2.6",
                displayName: "Kimi K2.6",
                maxContextLimit: 131_072,
                maxOutputTokens: 16_384,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "kimi-k2.5",
                displayName: "Kimi K2.5",
                maxContextLimit: 131_072,
                maxOutputTokens: 16_384,
                supportsImages: true,
                isRecommended: false
            ),
        ],
        authStyle: .bearer
    )

    // 9. OpenRouter
    private static let openRouter = ProviderDefinition(
        id: "openrouter",
        name: "OpenRouter",
        icon: "globe",
        shimProvider: "openai",
        defaultBaseURL: "https://openrouter.ai/api/v1",
        keyPlaceholder: "sk-or-...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://openrouter.ai/keys")!,
        models: [],   // Models fetched dynamically from /models endpoint
        authStyle: .bearer
    )

    // 10. Together AI
    private static let together = ProviderDefinition(
        id: "together",
        name: "Together AI",
        icon: "person.2",
        shimProvider: "openai",
        defaultBaseURL: "https://api.together.xyz/v1",
        keyPlaceholder: "Bearer token...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://api.together.xyz/settings/api-keys")!,
        models: [
            ProviderModelDef(
                modelId: "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8",
                displayName: "Llama 4 Maverick",
                maxContextLimit: 131_072,
                maxOutputTokens: 16_384,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "deepseek-ai/DeepSeek-R1",
                displayName: "DeepSeek R1",
                maxContextLimit: 128_000,
                maxOutputTokens: 8_192,
                supportsImages: false,
                isRecommended: false
            ),
            ProviderModelDef(
                modelId: "Qwen/Qwen3-235B-A22B",
                displayName: "Qwen3 235B",
                maxContextLimit: 131_072,
                maxOutputTokens: 16_384,
                supportsImages: false,
                isRecommended: false
            ),
        ],
        authStyle: .bearer
    )

    // 11. Fireworks AI
    private static let fireworks = ProviderDefinition(
        id: "fireworks",
        name: "Fireworks AI",
        icon: "sparkle",
        shimProvider: "openai",
        defaultBaseURL: "https://api.fireworks.ai/inference/v1",
        keyPlaceholder: "fw_...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://fireworks.ai/account/api-keys")!,
        models: [
            ProviderModelDef(
                modelId: "accounts/fireworks/models/llama4-maverick-instruct-basic",
                displayName: "Llama 4 Maverick",
                maxContextLimit: 131_072,
                maxOutputTokens: 16_384,
                supportsImages: true,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "accounts/fireworks/models/deepseek-r1",
                displayName: "DeepSeek R1",
                maxContextLimit: 128_000,
                maxOutputTokens: 8_192,
                supportsImages: false,
                isRecommended: false
            ),
        ],
        authStyle: .bearer
    )

    // 12. oMLX
    private static let omlx = ProviderDefinition(
        id: "omlx",
        name: "oMLX",
        icon: "cpu",
        shimProvider: "openai",
        defaultBaseURL: "http://localhost:8000/v1",
        keyPlaceholder: "None (local server)",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://omlx.ai")!,
        models: [
            ProviderModelDef(
                modelId: "llama3",
                displayName: "Llama 3 (Local)",
                maxContextLimit: 8192,
                maxOutputTokens: 2048,
                supportsImages: false,
                isRecommended: true
            )
        ],
        authStyle: .bearer
    )

    // 13. OpenCode Go
    private static let opencodeGo = ProviderDefinition(
        id: "opencode-go",
        name: "OpenCode Go",
        icon: "play.circle.fill",
        shimProvider: "openai",
        defaultBaseURL: "https://opencode.ai/zen/go/v1",
        keyPlaceholder: "oc-...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://opencode.ai")!,
        models: [
            ProviderModelDef(
                modelId: "qwen2.5-coder",
                displayName: "Qwen 2.5 Coder",
                maxContextLimit: 128_000,
                maxOutputTokens: 8_192,
                supportsImages: false,
                isRecommended: true
            ),
            ProviderModelDef(
                modelId: "deepseek-coder",
                displayName: "DeepSeek Coder",
                maxContextLimit: 128_000,
                maxOutputTokens: 8_192,
                supportsImages: false,
                isRecommended: true
            )
        ],
        authStyle: .bearer
    )

    // 14. Custom
    private static let custom = ProviderDefinition(
        id: "custom",
        name: "Custom",
        icon: "wrench.and.screwdriver",
        shimProvider: "generic-chat-completion-api",
        defaultBaseURL: "",
        keyPlaceholder: "API key...",
        keyValidationPath: "/models",
        docsURL: URL(string: "https://github.com/0xSero/codex-shim")!,
        models: [],   // User adds custom models
        authStyle: .bearer
    )
}
