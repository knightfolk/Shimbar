// MARK: - ModelsJsonManager.swift
// Shimbar – Manages reading and writing the models.json config file
// macOS 14+

import Foundation
import Observation

/// Manages the configuration file at `~/.codex-shim/models.json`.
@Observable
class ModelsJsonManager {
    static let shared = ModelsJsonManager()
    
    let modelsJsonURL: URL
    var models: [ShimModel] = []
    var routerConfig: RouterConfig?
    
    init(modelsJsonURL: URL? = nil) {
        let url = modelsJsonURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex-shim/models.json")
        self.modelsJsonURL = url
        try? ensureDirectoryExists()
    }
    
    /// Checks if we currently have any models configured.
    var hasModels: Bool {
        !models.isEmpty
    }
    
    /// Creates the `~/.codex-shim` directory if it does not already exist.
    func ensureDirectoryExists() throws {
        let dir = modelsJsonURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Loads the configuration from `~/.codex-shim/models.json`.
    func load() throws {
        ensureDirectoryExistsSafe()
        
        guard FileManager.default.fileExists(atPath: modelsJsonURL.path) else {
            self.models = []
            return
        }
        
        let data = try Data(contentsOf: modelsJsonURL)
        let decoder = JSONDecoder()
        
        // Suppress errors during loading if empty/malformed, fall back to empty
        do {
            let decodedFile = try decoder.decode(ModelsFile.self, from: data)
            self.models = decodedFile.models
            self.routerConfig = decodedFile.router
            
            // Decrypt keys from Keychain for models that don't have them in JSON but do have a provider
            var didDecryptAny = false
            for i in 0..<self.models.count {
                let model = self.models[i]
                if model.apiKey.isEmpty {
                    // Try to resolve provider ID based on URL or provider type
                    if let providerDef = ProviderCatalog.provider(forBaseURL: model.baseUrl) {
                        if let storedKey = KeychainManager.getKey(forProvider: providerDef.id) {
                            self.models[i].apiKey = storedKey
                            didDecryptAny = true
                        }
                    }
                }
            }
            if didDecryptAny {
                try? save()
            }
        } catch {
            self.models = []
            throw error
        }
    }
    
    /// Saves the current list of models to `~/.codex-shim/models.json` atomically with a backup.
    func save() throws {
        try ensureDirectoryExists()
        
        // Backup API keys securely to Keychain while keeping them in models.json so codex-shim proxy can read them.
        var modelsToSave: [ShimModel] = []
        for model in models {
            var modelCopy = model
            if !model.apiKey.isEmpty {
                if let providerDef = ProviderCatalog.provider(forBaseURL: model.baseUrl) {
                    try? KeychainManager.saveKey(model.apiKey, forProvider: providerDef.id)
                }
            }
            modelsToSave.append(modelCopy)
        }
        
        let fileObj = ModelsFile(models: modelsToSave, router: routerConfig)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(fileObj)
        
        // Atomic write with .bak backup
        let bakURL = modelsJsonURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: modelsJsonURL.path) {
            try? FileManager.default.removeItem(at: bakURL)
            try FileManager.default.copyItem(at: modelsJsonURL, to: bakURL)
        }
        
        try data.write(to: modelsJsonURL, options: .atomic)
        
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: modelsJsonURL.path)
    }
    
    /// Adds one or more selected models for a given provider, merging with the existing models list.
    func addModels(for provider: ProviderDefinition, selectedModels: [ProviderModelDef], apiKey: String) throws {
        try load()
        
        // Save the API key securely to Keychain
        if !apiKey.isEmpty {
            try? KeychainManager.saveKey(apiKey, forProvider: provider.id)
        }
        
        // Filter out existing models for this specific base URL to avoid duplicates/conflicts
        models.removeAll { $0.baseUrl == provider.defaultBaseURL }
        
        // Create new ShimModel objects
        for modelDef in selectedModels {
            let slugName: String
            if provider.id == "openai" {
                slugName = modelDef.modelId
            } else {
                slugName = "\(provider.id)-\(modelDef.modelId)"
            }
            
            let providerDisplayName: String
            if provider.id == "zhipu" {
                providerDisplayName = "Z.AI"
            } else if provider.id == "opencode-go" {
                providerDisplayName = "OC"
            } else {
                providerDisplayName = provider.name
            }
            
            let newModel = ShimModel(
                slug: slugName,
                model: modelDef.modelId,
                displayName: "\(providerDisplayName) \(modelDef.displayName)",
                provider: provider.shimProvider,
                baseUrl: provider.defaultBaseURL,
                apiKey: apiKey,
                maxContextLimit: modelDef.maxContextLimit,
                maxOutputTokens: modelDef.maxOutputTokens,
                noImageSupport: !modelDef.supportsImages,
                extraHeaders: [:]
            )
            models.append(newModel)
        }
        
        try save()
    }
    
    /// Removes all models associated with a provider ID (by matching base URL, slug prefix, or normalized base URL).
    func removeProvider(_ providerId: String) throws {
        try load()
        
        let normalizedProviderId = providerId.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        
        // Remove from Keychain
        try? KeychainManager.deleteKey(forProvider: providerId)
        
        // Let's filter models array
        models.removeAll { model in
            let modelBaseUrlNormalized = model.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            
            // 1. If it's a known provider ID, we match by:
            if let provider = ProviderCatalog.provider(forId: providerId) {
                let providerBaseUrlNormalized = provider.defaultBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
                
                // - exact or normalized defaultBaseURL match
                if modelBaseUrlNormalized == providerBaseUrlNormalized || model.baseUrl == provider.defaultBaseURL {
                    return true
                }
                
                // - slug prefix match (e.g., "zhipu-")
                if model.slug.lowercased().hasPrefix("\(providerId.lowercased())-") {
                    return true
                }
            }
            
            // 2. If it's a custom provider / URL-based match:
            if modelBaseUrlNormalized == normalizedProviderId || model.baseUrl == providerId {
                return true
            }
            
            // 3. Fallback slug prefix match
            if model.slug.lowercased().hasPrefix("\(providerId.lowercased())-") {
                return true
            }
            
            return false
        }
        
        try save()
    }
    
    /// Updates the API key for all models using the given base URL.
    func updateApiKey(for baseUrl: String, newKey: String) throws {
        try load()
        
        // Save the API key securely in Keychain if matched to a provider
        if let provider = ProviderCatalog.provider(forBaseURL: baseUrl) {
            try? KeychainManager.saveKey(newKey, forProvider: provider.id)
        }
        
        for i in 0..<models.count {
            if models[i].baseUrl == baseUrl {
                models[i].apiKey = newKey
            }
        }
        
        try save()
    }
    
    /// Groups currently loaded models by their base URL and tries to pair them with a known provider.
    func providerGroups() -> [(providerDef: ProviderDefinition?, baseUrl: String, models: [ShimModel])] {
        let grouped = Dictionary(grouping: models) { $0.baseUrl }
        
        var result: [(providerDef: ProviderDefinition?, baseUrl: String, models: [ShimModel])] = []
        for (baseUrl, groupModels) in grouped {
            let provider = ProviderCatalog.provider(forBaseURL: baseUrl)
            result.append((providerDef: provider, baseUrl: baseUrl, models: groupModels))
        }
        
        return result.sorted { ($0.providerDef?.name ?? $0.baseUrl) < ($1.providerDef?.name ?? $1.baseUrl) }
    }
    
    private func ensureDirectoryExistsSafe() {
        try? ensureDirectoryExists()
    }
}
