import Foundation

enum CatalogEntry {

    static let planTiers = ["free", "plus", "pro", "team", "business", "enterprise"]

    static func defaultContext(for model: ShimModel) -> Int {
        if let ctx = model.maxContextLimit, ctx > 0 {
            return ctx
        }
        return defaultContextByFamily(model: model.model, displayName: model.displayName)
    }

    static func defaultContextByFamily(model: String, displayName: String) -> Int {
        let combined = "\(model) \(displayName)".lowercased()
        if combined.contains("claude") { return 200_000 }
        if combined.contains("gpt-5") { return 400_000 }
        if combined.contains("gemini") { return 1_000_000 }
        return 128_000
    }

    static func truncationLimit(context: Int) -> Int {
        min(64_000, max(8_000, Int(Double(context) * 0.32)))
    }

    static func autoCompactLimit(context: Int) -> Int {
        max(8_000, Int(Double(context) * 0.8))
    }

    static func reasoningEffort(displayName: String) -> String {
        let lower = displayName.lowercased()
        if lower.contains("xhigh") || lower.contains("x-high") { return "xhigh" }
        if lower.contains("high") { return "high" }
        if lower.contains("medium") { return "medium" }
        if lower.contains("low") { return "low" }
        return "medium"
    }

    static func priority(index: Int) -> Int {
        max(1, 1000 - index)
    }

    static func makeEntry(for model: ShimModel, index: Int) -> [String: Any] {
        let context = defaultContext(for: model)
        let compact = autoCompactLimit(context: context)
        let truncation = truncationLimit(context: context)
        let reasoning = reasoningEffort(displayName: model.displayName)
        let inputModalities: [String] = model.noImageSupport ? ["text"] : ["text", "image"]

        return [
            "slug": model.slug,
            "display_name": model.displayName,
            "description": "\(model.displayName) via local Codex shim.",
            "context_window": context,
            "max_context_window": context,
            "auto_compact_token_limit": compact,
            "truncation_policy": ["mode": "tokens", "limit": truncation] as [String: Any],
            "default_reasoning_level": reasoning,
            "supported_reasoning_levels": [
                ["effort": "low", "description": "Faster, lighter reasoning"],
                ["effort": "medium", "description": "Balanced speed and reasoning"],
                ["effort": "high", "description": "Deeper reasoning"],
                ["effort": "xhigh", "description": "Maximum reasoning where supported"]
            ] as [[String: String]],
            "default_reasoning_summary": "none",
            "reasoning_summary_format": "none",
            "supports_reasoning_summaries": false,
            "default_verbosity": "low",
            "support_verbosity": false,
            "apply_patch_tool_type": "freeform",
            "web_search_tool_type": "text_and_image",
            "supports_search_tool": false,
            "supports_parallel_tool_calls": true,
            "experimental_supported_tools": [] as [Any],
            "input_modalities": inputModalities,
            "supports_image_detail_original": !model.noImageSupport,
            "shell_type": "shell_command",
            "visibility": "list",
            "minimal_client_version": "0.0.1",
            "supported_in_api": true,
            "availability_nux": NSNull(),
            "upgrade": NSNull(),
            "priority": priority(index: index),
            "prefer_websockets": false,
            "available_in_plans": planTiers,
            "base_instructions": "You are a coding agent running in Codex through a local BYOK shim.",
            "model_messages": [
                "instructions_template": "You are Codex running on \(model.displayName) through a local all-model shim. Be a helpful, direct coding collaborator.",
                "instructions_variables": ["model_name": model.displayName]
            ] as [String: Any]
        ]
    }

    static func routerEntry(for config: RouterConfig) -> [String: Any] {
        return [
            "slug": config.slug,
            "display_name": config.displayName,
            "description": "Automatically routes each task to the cheapest configured model that can handle it.",
            "context_window": 400_000,
            "max_context_window": 400_000,
            "auto_compact_token_limit": 320_000,
            "truncation_policy": ["mode": "tokens", "limit": 64_000] as [String: Any],
            "default_reasoning_level": "medium",
            "supported_reasoning_levels": [
                ["effort": "low", "description": "Faster, lighter reasoning"],
                ["effort": "medium", "description": "Balanced speed and reasoning"],
                ["effort": "high", "description": "Deeper reasoning"],
                ["effort": "xhigh", "description": "Maximum reasoning where supported"]
            ] as [[String: String]],
            "default_reasoning_summary": "none",
            "reasoning_summary_format": "none",
            "supports_reasoning_summaries": false,
            "default_verbosity": "low",
            "support_verbosity": false,
            "apply_patch_tool_type": "freeform",
            "web_search_tool_type": "text_and_image",
            "supports_search_tool": false,
            "supports_parallel_tool_calls": true,
            "experimental_supported_tools": [] as [Any],
            "input_modalities": ["text", "image"],
            "supports_image_detail_original": true,
            "shell_type": "shell_command",
            "visibility": "list",
            "minimal_client_version": "0.0.1",
            "supported_in_api": true,
            "availability_nux": NSNull(),
            "upgrade": NSNull(),
            "priority": 12000,
            "prefer_websockets": false,
            "available_in_plans": planTiers,
            "base_instructions": "You are Codex, a coding agent. The active model is chosen automatically per task.",
            "model_messages": [
                "instructions_template": "You are Codex, a coding agent. The active model is chosen automatically per task.",
                "instructions_variables": ["model_name": config.displayName]
            ] as [String: Any]
        ]
    }
}
