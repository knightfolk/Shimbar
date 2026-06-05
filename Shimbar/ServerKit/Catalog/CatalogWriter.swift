import Foundation

enum CatalogWriter {

    static let providerName = "codex_shim"

    static var catalogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-shim/custom_model_catalog.json")
    }

    static func write(
        models: [ShimModel],
        routerConfig: RouterConfig?,
        chatgptAvailable: Bool = false,
        to url: URL = catalogURL
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var entries: [[String: Any]] = []

        if let router = routerConfig, router.enabled {
            let candidateSlugs = Set(models.filter { !$0.apiKey.isEmpty }.map(\.slug))
            let hasUsableCandidates = router.candidates.contains { candidateSlugs.contains($0.slug) }
            if hasUsableCandidates {
                entries.append(CatalogEntry.routerEntry(for: router))
            }
        }

        if chatgptAvailable {
            let chatgptEntries = ChatGPTCatalog.loadEntries()
            for entry in chatgptEntries {
                var dict: [String: Any] = [
                    "slug": entry.slug,
                    "display_name": entry.displayName,
                    "context_window": entry.contextWindow,
                    "priority": entry.priority,
                    "visibility": "list",
                    "minimal_client_version": "0.0.1",
                    "supported_in_api": true,
                    "available_in_plans": CatalogEntry.planTiers
                ]
                if entry.slug == ChatGPTCatalog.defaultUpstreamModel {
                    dict["isDefault"] = true
                    dict["priority"] = max(entry.priority, 10000)
                }
                entries.append(dict)
            }
        }

        let usable = models.enumerated().filter { !$0.element.apiKey.isEmpty }
        for (arrayIndex, model) in usable {
            entries.append(CatalogEntry.makeEntry(for: model, index: arrayIndex))
        }

        let payload: [String: Any] = ["models": entries]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        return url
    }
}
