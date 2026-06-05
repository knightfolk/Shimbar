import Foundation

// MARK: - ChatGPT Catalog Slugs

/// Slug constants and on-disk catalog reader for the ChatGPT passthrough
/// models exposed to the Codex picker.
enum ChatGPTCatalog {

    /// Default upstream model used when a request carries the `openai-gpt-*`
    /// prefix but the on-disk catalog doesn't list a more specific match.
    static let defaultUpstreamModel = "gpt-5.5"

    /// Fallback slugs returned when `~/.codex/models_cache.json` is missing
    /// or contains no usable entries. Mirrors the Python
    /// ``FALLBACK_CHATGPT_PASSTHROUGH_SLUGS`` constant in lockstep.
    static let fallbackSlugs: [String] = [
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.3-codex",
        "gpt-5.3-codex-spark",
        "gpt-5.2",
        "codex-auto-review",
    ]

    /// Display names for the fallback slugs. Used to populate the picker when
    /// the upstream catalog has not yet been fetched.
    static let fallbackDisplayNames: [String: String] = [
        "gpt-5.5": "GPT-5.5",
        "gpt-5.4": "gpt-5.4",
        "gpt-5.4-mini": "GPT-5.4-Mini",
        "gpt-5.3-codex": "gpt-5.3-codex",
        "gpt-5.3-codex-spark": "GPT-5.3-Codex-Spark",
        "gpt-5.2": "gpt-5.2",
        "codex-auto-review": "Codex Auto Review",
    ]

    // MARK: - Paths

    /// Resolved path to the on-disk `models_cache.json`. Overridable via the
    /// `CODEX_SHIM_MODELS_CACHE_PATH` env var (used by tests).
    static var modelsCachePath: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_SHIM_MODELS_CACHE_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("models_cache.json")
    }

    // MARK: - Slug Classification

    /// Returns `true` if the slug is one we know how to route through the
    /// ChatGPT passthrough. Recognises both the `openai-gpt-*` prefix and any
    /// slug enumerated in `~/.codex/models_cache.json`.
    /// - Parameter slug: The slug carried in the request body or picker.
    /// - Returns: `true` when the request should be forwarded to ChatGPT.
    static func isChatGPTPassthroughSlug(_ slug: String) -> Bool {
        if slug.hasPrefix("openai-gpt-") {
            return true
        }
        return loadSlugs().contains(slug)
    }

    /// Returns the upstream model name to send to ChatGPT for a given picker
    /// slug. Mirrors the Python ``chatgpt_upstream_model`` mapping.
    static func upstreamModel(for slug: String) -> String {
        if slug.hasPrefix("openai-gpt-") {
            return defaultUpstreamModel
        }
        if loadSlugs().contains(slug) {
            return slug
        }
        return defaultUpstreamModel
    }

    // MARK: - Catalog Loaders

    /// Returns the slugs the picker should advertise for the ChatGPT
    /// passthrough. Falls back to ``fallbackSlugs`` when the cache is missing
    /// or contains no usable entries.
    /// - Parameter cachePath: Optional override for the on-disk cache file.
    /// - Returns: A deterministic, sorted set of slug strings.
    static func loadSlugs(cachePath: URL? = nil) -> Set<String> {
        Set(loadEntries(cachePath: cachePath).compactMap { $0.slug })
    }

    /// Returns slug -> display name pairs for the picker.
    /// - Parameter cachePath: Optional override for the on-disk cache file.
    /// - Returns: Dictionary of slug to display name.
    static func loadDisplayNames(cachePath: URL? = nil) -> [String: String] {
        var out: [String: String] = [:]
        for entry in loadEntries(cachePath: cachePath) {
            if !entry.slug.isEmpty {
                out[entry.slug] = entry.displayName.isEmpty ? entry.slug : entry.displayName
            }
        }
        return out
    }

    /// Returns the list of catalog entries (slug, display name, context window,
    /// etc.) — either loaded from disk or the built-in fallback list.
    /// - Parameter cachePath: Optional override for the on-disk cache file.
    /// - Returns: A list of catalog entries.
    static func loadEntries(cachePath: URL? = nil) -> [ChatGPTCatalogEntry] {
        let path = cachePath ?? modelsCachePath
        guard FileManager.default.fileExists(atPath: path.path) else {
            return fallbackEntries()
        }
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else {
            return fallbackEntries()
        }
        let entries = models.compactMap { raw -> ChatGPTCatalogEntry? in
            guard let slug = raw["slug"] as? String,
                  Self.isListedGPTSlug(slug, raw: raw)
            else { return nil }
            return ChatGPTCatalogEntry(
                slug: slug,
                displayName: raw["display_name"] as? String ?? slug,
                contextWindow: (raw["context_window"] as? Int) ?? 400_000,
                priority: (raw["priority"] as? Int) ?? 9000
            )
        }
        if entries.isEmpty {
            return fallbackEntries()
        }
        return entries
    }

    /// Returns the fallback entries synthesised from
    /// ``fallbackSlugs``/``fallbackDisplayNames``.
    /// - Returns: A list of catalog entries.
    static func fallbackEntries() -> [ChatGPTCatalogEntry] {
        fallbackSlugs.enumerated().map { index, slug in
            ChatGPTCatalogEntry(
                slug: slug,
                displayName: fallbackDisplayNames[slug] ?? slug,
                contextWindow: 400_000,
                priority: slug == defaultUpstreamModel ? 10_000 : 9_000 - index
            )
        }
    }

    // MARK: - Helpers

    /// Slug filter matching the Python ``_is_listed_gpt_model``: `gpt-` or
    /// `codex-` prefix, non-hidden, and non-empty.
    static func isListedGPTSlug(_ slug: String, raw: [String: Any]) -> Bool {
        let trimmed = slug.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if (raw["visibility"] as? String)?.lowercased() == "hidden" {
            return false
        }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("gpt-") || lower.hasPrefix("codex-")
    }
}

// MARK: - ChatGPTCatalogEntry

/// A single catalog entry for a ChatGPT-passthrough model exposed in the
/// picker. Only carries the fields the picker needs to render the row; full
/// capability metadata is fetched from the on-disk cache when present.
struct ChatGPTCatalogEntry: Equatable, Sendable {
    var slug: String
    var displayName: String
    var contextWindow: Int
    var priority: Int
}
