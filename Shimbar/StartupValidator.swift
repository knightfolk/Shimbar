// MARK: - StartupValidator.swift
// Shimbar – Dependency and permission validator engine
// macOS 14+

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class StartupValidator {
    
    enum CheckStatus: Equatable {
        case checking
        case success
        case warning(String) // Non-blocking issue (e.g. Codex missing, can't patch but can use general shim)
        case failure(String) // Blocking issue (e.g. codex-shim binary missing)
        
        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
        
        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }
        
        var isWarning: Bool {
            if case .warning = self { return true }
            return false
        }
    }
    
    struct CheckItem: Identifiable {
        let id: String
        let title: String
        let description: String
        var status: CheckStatus
        let isCritical: Bool
    }
    
    /// List of check items being displayed in the onboarding checklist
    var items: [CheckItem] = []
    
    /// Global check state
    var isChecking = false
    
    /// True if there's any critical failure that blocks the app from being used
    var hasCriticalFailures: Bool {
        items.contains { $0.isCritical && $0.status.isFailure }
    }
    
    /// True if onboarding checks have completed and all critical dependencies are green
    var isFullyReady: Bool {
        !items.isEmpty && !hasCriticalFailures && !isChecking
    }
    
    init() {
        resetItems()
    }
    
    func resetItems() {
        self.items = [
            CheckItem(
                id: "binary",
                title: "codex-shim binary",
                description: "Checks if the codex-shim CLI binary is found on your Mac.",
                status: .checking,
                isCritical: true
            ),
            CheckItem(
                id: "models",
                title: "Active AI Models",
                description: "Checks if models.json is configured with at least one AI provider model.",
                status: .checking,
                isCritical: true
            ),
            CheckItem(
                id: "codexApp",
                title: "Codex Desktop App (Optional)",
                description: "Verifies if the official Codex.app is installed in /Applications.",
                status: .checking,
                isCritical: false
            ),
            CheckItem(
                id: "npx",
                title: "Node.js (npx) Tool (Optional)",
                description: "Verifies if 'npx' is installed. Required to unpack Codex for patching.",
                status: .checking,
                isCritical: false
            ),
            CheckItem(
                id: "writePerm",
                title: "Codex Signature Access (Optional)",
                description: "Verifies write permissions to allow modifying and re-signing Codex.",
                status: .checking,
                isCritical: false
            )
        ]
    }
    
    /// Perform all validation checks asynchronously
    func performAllChecks() async {
        isChecking = true
        resetItems()
        
        // 1. Check codex-shim binary
        await checkBinary()
        
        // 2. Check models.json configuration
        await checkModels()
        
        // 3. Check Codex Desktop presence
        let hasCodex = await checkCodexApp()
        
        // 4. Check Node.js / npx presence
        let hasNpx = await checkNpx()
        
        // 5. Check signature write permission
        await checkWritePermissions(hasCodex: hasCodex, hasNpx: hasNpx)
        
        isChecking = false
    }
    
    // MARK: - Core Validators
    
    private func updateStatus(for id: String, status: CheckStatus) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].status = status
        }
    }
    
    private func checkBinary() async {
        updateStatus(for: "binary", status: .checking)
        
        // Ensure ShimManager path discovery is triggered/synced
        await ShimManager.shared.rediscoverShimPath()
        
        if ShimManager.shared.shimFound {
            updateStatus(for: "binary", status: .success)
        } else {
            updateStatus(for: "binary", status: .failure("codex-shim binary was not found. Please install it globally or select it manually."))
        }
    }
    
    private func checkModels() async {
        updateStatus(for: "models", status: .checking)
        
        // Load latest models.json
        do {
            try ModelsJsonManager.shared.load()
            if ModelsJsonManager.shared.hasModels {
                updateStatus(for: "models", status: .success)
            } else {
                updateStatus(for: "models", status: .failure("No AI models are configured yet. You must add at least one AI provider."))
            }
        } catch {
            updateStatus(for: "models", status: .failure("Failed to load models.json: \(error.localizedDescription)"))
        }
    }
    
    private func checkCodexApp() async -> Bool {
        updateStatus(for: "codexApp", status: .checking)
        
        let path = "/Applications/Codex.app"
        let exists = FileManager.default.fileExists(atPath: path)
        
        if exists {
            updateStatus(for: "codexApp", status: .success)
            return true
        } else {
            updateStatus(for: "codexApp", status: .warning("Codex.app not found in /Applications. You won't be able to patch it, but you can still run the shim."))
            return false
        }
    }
    
    private func checkNpx() async -> Bool {
        updateStatus(for: "npx", status: .checking)
        
        if let npxPath = await ProcessRunner.which("npx") {
            let path = npxPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                updateStatus(for: "npx", status: .success)
                return true
            }
        }
        
        updateStatus(for: "npx", status: .warning("'npx' was not found on your system path. Node.js is required to patch Codex.app."))
        return false
    }
    
    private func checkWritePermissions(hasCodex: Bool, hasNpx: Bool) async {
        updateStatus(for: "writePerm", status: .checking)
        
        guard hasCodex else {
            updateStatus(for: "writePerm", status: .warning("Cannot check write access because Codex.app is missing."))
            return
        }
        
        let appAsarPath = "/Applications/Codex.app/Contents/Resources/app.asar"
        let isWritable = FileManager.default.isWritableFile(atPath: appAsarPath)
        
        if isWritable {
            updateStatus(for: "writePerm", status: .success)
        } else {
            updateStatus(for: "writePerm", status: .warning("Cannot write to Codex app.asar. You may need to grant Full Disk Access to Shimbar, or repair write permissions."))
        }
    }
}
