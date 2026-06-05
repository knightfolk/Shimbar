import Foundation

enum CodexConfigPatcher {

    private static let managedBegin = "# >>> codex-shim managed >>>"
    private static let managedEnd = "# <<< codex-shim managed <<<"
    private static let previousTopLevelPrefix = "# codex-shim previous-top-level = "
    private static let managedTopLevelKeys: Set<String> = ["model", "model_provider", "model_catalog_json"]

    static var codexConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
    }

    static var codexConfigBackupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-shim/config.toml.before-codex-shim")
    }

    // MARK: - Install

    static func install(
        defaultSlug: String,
        catalogPath: String,
        port: Int,
        configURL: URL = codexConfigURL
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: codexConfigBackupURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let original: String
        if fm.fileExists(atPath: configURL.path) {
            original = try String(contentsOf: configURL, encoding: .utf8)
        } else {
            original = ""
        }

        var cleaned = removeManagedBlocks(from: original)
        let currentTopLevel = extractTopLevelKeyLines(from: cleaned, keys: managedTopLevelKeys)

        let previousTopLevel: [String: String]
        if !currentTopLevel.isEmpty {
            previousTopLevel = currentTopLevel
        } else {
            previousTopLevel = managedPreviousTopLevel(from: original)
        }

        cleaned = removeTopLevelKeys(from: cleaned, keys: managedTopLevelKeys)
        cleaned = removeSection(from: cleaned, section: "model_providers.\(CatalogWriter.providerName)")

        let topBlock = makeTopBlock(defaultSlug: defaultSlug, catalogPath: catalogPath, previousTopLevel: previousTopLevel)
        let providerBlock = makeProviderBlock(port: port)

        let result = topBlock + "\n" + cleaned.lstrip() + "\n" + providerBlock
        try result.data(using: .utf8)?.write(to: configURL, options: .atomic)
    }

    // MARK: - Restore

    static func restore(configURL: URL = codexConfigURL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return }

        let current = try String(contentsOf: configURL, encoding: .utf8)
        var previousTopLevel = managedPreviousTopLevel(from: current)
        if previousTopLevel.isEmpty && fm.fileExists(atPath: codexConfigBackupURL.path) {
            let backup = try String(contentsOf: codexConfigBackupURL, encoding: .utf8)
            previousTopLevel = extractTopLevelKeyLines(from: backup, keys: managedTopLevelKeys)
        }

        var restored = removeManagedBlocks(from: current)
        restored = removeSection(from: restored, section: "model_providers.\(CatalogWriter.providerName)")
        restored = restoreMissingTopLevelKeys(to: restored.lstrip(), previous: previousTopLevel)

        try restored.data(using: .utf8)?.write(to: configURL, options: .atomic)

        if fm.fileExists(atPath: codexConfigBackupURL.path) {
            try? fm.removeItem(at: codexConfigBackupURL)
        }
    }

    // MARK: - Block Builders

    private static func makeTopBlock(
        defaultSlug: String,
        catalogPath: String,
        previousTopLevel: [String: String]
    ) -> String {
        var metadataLine = ""
        if !previousTopLevel.isEmpty {
            let sorted = previousTopLevel.sorted { $0.key < $1.key }
            let dict: [String: String] = Dictionary(uniqueKeysWithValues: sorted.map { ($0.key, $0.value.trimmingCharacters(in: .whitespaces)) })
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys),
               let json = String(data: data, encoding: .utf8) {
                metadataLine = previousTopLevelPrefix + json + "\n"
            }
        }
        return """
        \(managedBegin)
        \(metadataLine)model = "\(TOMLEscaper.escape(defaultSlug))"
        model_provider = "\(CatalogWriter.providerName)"
        model_catalog_json = "\(TOMLEscaper.escape(catalogPath))"
        \(managedEnd)
        """
    }

    private static func makeProviderBlock(port: Int) -> String {
        """
        \(managedBegin)
        [model_providers.\(CatalogWriter.providerName)]
        name = "Codex Shim"
        base_url = "http://127.0.0.1:\(port)/v1"
        wire_api = "responses"
        experimental_bearer_token = "dummy"
        request_max_retries = 3
        stream_max_retries = 3
        stream_idle_timeout_ms = 600000
        \(managedEnd)
        """
    }

    // MARK: - Text Manipulation

    static func removeManagedBlocks(from text: String) -> String {
        var result = text
        while let beginRange = result.range(of: managedBegin) {
            let afterBegin = beginRange.upperBound
            guard let endRange = result.range(of: managedEnd, range: afterBegin..<result.endIndex) else {
                result.removeSubrange(beginRange.lowerBound..<result.endIndex)
                break
            }
            result.removeSubrange(beginRange.lowerBound..<endRange.upperBound)
        }
        return result
    }

    static func removeTopLevelKeys(from text: String, keys: Set<String>) -> String {
        var lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var inTopLevel = true
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                inTopLevel = false
            }
            var key = ""
            if let eq = stripped.firstIndex(of: "=") {
                key = String(stripped[stripped.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            }
            if inTopLevel && keys.contains(key) {
                continue
            }
            output.append(line)
        }
        var result = output.joined(separator: "\n")
        if text.hasSuffix("\n") { result += "\n" }
        return result
    }

    static func extractTopLevelKeyLines(from text: String, keys: Set<String>) -> [String: String] {
        var found: [String: String] = [:]
        var inTopLevel = true
        for line in text.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                inTopLevel = false
            }
            if !inTopLevel || stripped.isEmpty || stripped.hasPrefix("#") { continue }
            guard let eq = stripped.firstIndex(of: "=") else { continue }
            let key = String(stripped[stripped.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            if keys.contains(key) {
                found[key] = line
            }
        }
        return found
    }

    static func managedPreviousTopLevel(from text: String) -> [String: String] {
        var inManaged = false
        for line in text.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped == managedBegin {
                inManaged = true
                continue
            }
            if stripped == managedEnd {
                inManaged = false
                continue
            }
            if inManaged && stripped.hasPrefix(previousTopLevelPrefix) {
                let encoded = String(stripped.dropFirst(previousTopLevelPrefix.count))
                if let data = encoded.data(using: .utf8),
                   let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    return payload.filter { managedTopLevelKeys.contains($0.key) }
                }
                return [:]
            }
        }
        return [:]
    }

    static func removeSection(from text: String, section: String) -> String {
        let header = "[\(section)]"
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var skipping = false
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                skipping = (stripped == header)
                if skipping { continue }
            }
            if !skipping {
                output.append(line)
            }
        }
        var result = output.joined(separator: "\n")
        if text.hasSuffix("\n") { result += "\n" }
        return result
    }

    private static func restoreMissingTopLevelKeys(to text: String, previous: [String: String]) -> String {
        guard !previous.isEmpty else { return text }
        let current = extractTopLevelKeyLines(from: text, keys: managedTopLevelKeys)
        let orderedKeys = ["model", "model_provider", "model_catalog_json"]
        let lines = orderedKeys.compactMap { key -> String? in
            guard let line = previous[key], current[key] == nil else { return nil }
            return line
        }
        guard !lines.isEmpty else { return text }
        let prefix = lines.joined(separator: "\n") + "\n"
        if text.isEmpty { return prefix }
        return prefix + text
    }
}

private extension String {
    func lstrip() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
