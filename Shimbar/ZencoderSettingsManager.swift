import Foundation
import AppKit

@Observable
final class ZencoderSettingsManager {
    static let shared = ZencoderSettingsManager()
    
    private let fileManager = FileManager.default
    private let syncQueue = DispatchQueue(label: "com.shimbar.zencoder.sync")
    
    var lastError: String?
    
    private var settingsDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zencoder")
    }
    
    private var settingsFileURL: URL {
        settingsDirectoryURL.appendingPathComponent("settings.json")
    }
    
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "shimbar.zencoderSyncEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "shimbar.zencoderSyncEnabled")
            if newValue {
                syncFromShimbar()
            }
        }
    }
    
    var exportedProviderIds: Set<String> = []
    
    private init() {
        if !fileManager.fileExists(atPath: settingsDirectoryURL.path) {
            try? fileManager.createDirectory(at: settingsDirectoryURL, withIntermediateDirectories: true)
        }
        syncQueue.sync {
            if let settings = try? readSettingsFile() {
                exportedProviderIds = Set(settings.providers.keys)
            }
        }
    }
    
    private func readSettingsFile() throws -> ZencoderSettingsFile {
        guard fileManager.fileExists(atPath: settingsFileURL.path) else {
            return ZencoderSettingsFile()
        }
        let data = try Data(contentsOf: settingsFileURL)
        return try JSONDecoder().decode(ZencoderSettingsFile.self, from: data)
    }
    
    private func writeSettingsFile(_ settingsFile: ZencoderSettingsFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settingsFile)
        
        if fileManager.fileExists(atPath: settingsFileURL.path) {
            let backupURL = settingsDirectoryURL.appendingPathComponent("settings.json.bak")
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: settingsFileURL, to: backupURL)
        }
        
        try data.write(to: settingsFileURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsFileURL.path)
    }
    
    func load() throws -> ZencoderSettingsFile {
        var result: Result<ZencoderSettingsFile, Error>!
        syncQueue.sync {
            do {
                let settings = try readSettingsFile()
                exportedProviderIds = Set(settings.providers.keys)
                result = .success(settings)
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }
    
    func save(_ settingsFile: ZencoderSettingsFile) throws {
        var thrownError: Error?
        syncQueue.sync {
            do {
                try writeSettingsFile(settingsFile)
                exportedProviderIds = Set(settingsFile.providers.keys)
            } catch {
                thrownError = error
            }
        }
        if let error = thrownError { throw error }
    }
    
    func exportProvider(_ providerId: String, baseUrl: String, apiKey: String, models: [ShimModel]) {
        syncQueue.sync {
            do {
                var settings = try readSettingsFile()
                
                var zencoderModels: [String: ZencoderModel] = [:]
                for model in models {
                    zencoderModels[model.slug] = ZencoderModel(
                        name: model.model,
                        displayName: model.displayName,
                        options: ZencoderModelOptions(
                            temperature: nil,
                            maxOutputTokens: model.maxOutputTokens
                        )
                    )
                }
                
                settings.providers[providerId] = ZencoderProvider(
                    mode: "direct",
                    type: "openai-compatible",
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    models: zencoderModels
                )
                
                try writeSettingsFile(settings)
                exportedProviderIds = Set(settings.providers.keys)
                lastError = nil
            } catch {
                lastError = "Failed to export provider: \(error.localizedDescription)"
                DebugLogger.log("Failed to export provider to Zencoder: \(error)")
            }
        }
    }
    
    func removeProvider(_ providerId: String) {
        syncQueue.sync {
            do {
                var settings = try readSettingsFile()
                if settings.providers.removeValue(forKey: providerId) != nil {
                    try writeSettingsFile(settings)
                    exportedProviderIds = Set(settings.providers.keys)
                }
                lastError = nil
            } catch {
                lastError = "Failed to remove provider: \(error.localizedDescription)"
                DebugLogger.log("Failed to remove provider from Zencoder: \(error)")
            }
        }
    }
    
    func syncFromShimbar(forceAll: Bool = false) {
        syncQueue.sync {
            DebugLogger.log("syncFromShimbar started with forceAll=\(forceAll)")
            let groups = ModelsJsonManager.shared.providerGroups()
            DebugLogger.log("Found \(groups.count) provider groups")
            
            do {
                var settings = try readSettingsFile()
                exportedProviderIds = Set(settings.providers.keys)
                DebugLogger.log("Loaded settings successfully. Current providers: \(settings.providers.keys)")
                
                for group in groups {
                    guard let providerDef = group.providerDef else { continue }
                    let providerId = providerDef.id
                    
                    if forceAll || isEnabled || exportedProviderIds.contains(providerId) {
                        let apiKey = KeychainManager.getKey(forProvider: providerId) ?? group.models.first?.apiKey ?? ""
                        
                        var zencoderModels: [String: ZencoderModel] = [:]
                        for model in group.models {
                            zencoderModels[model.slug] = ZencoderModel(
                                name: model.model,
                                displayName: model.displayName,
                                options: ZencoderModelOptions(
                                    temperature: nil,
                                    maxOutputTokens: model.maxOutputTokens
                                )
                            )
                        }
                        
                        settings.providers[providerId] = ZencoderProvider(
                            mode: "direct",
                            type: "openai-compatible",
                            baseUrl: group.baseUrl,
                            apiKey: apiKey,
                            models: zencoderModels
                        )
                        DebugLogger.log("Added/Updated provider \(providerId) with \(zencoderModels.count) models")
                    } else {
                        DebugLogger.log("Skipped provider \(providerId) because forceAll=false, isEnabled=\(isEnabled), and not in exportedProviderIds")
                    }
                }
                
                DebugLogger.log("Attempting to save settings...")
                try writeSettingsFile(settings)
                exportedProviderIds = Set(settings.providers.keys)
                lastError = nil
                DebugLogger.log("Settings saved successfully!")
            } catch {
                lastError = "Failed to sync settings: \(error.localizedDescription)"
                DebugLogger.log("Failed to sync Zencoder settings from Shimbar: \(error)")
            }
        }
    }
    
    func openSettingsInFinder() {
        NSWorkspace.shared.selectFile(settingsFileURL.path, inFileViewerRootedAtPath: settingsDirectoryURL.path)
    }
}
