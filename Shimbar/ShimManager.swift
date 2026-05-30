// ShimManager.swift
// Shimbar
//
// Central business logic class that wraps codex-shim CLI commands
// and manages application state for the menu bar app.

import Foundation
import SwiftUI
import Observation

// MARK: - ShimManager

/// The central manager that orchestrates all interactions with the codex-shim CLI.
///
/// `ShimManager` is the single source of truth for the shim's runtime state,
/// including whether it's running, which model is active, and what providers
/// are configured. All CLI invocations go through ``ProcessRunner`` and state
/// is published to SwiftUI views via the `@Observable` macro.
@MainActor
@Observable
final class ShimManager {

    // MARK: - Singleton

    static let shared = ShimManager()

    // MARK: - Published State

    /// Current operational status of the shim process.
    var status: ShimStatus = .unknown

    /// Whether the shim is fully enabled (config installed + process running).
    var isEnabled: Bool = false

    /// Whether the Codex Desktop app is currently patched.
    var isCodexPatched: Bool = false

    /// All models loaded from `models.json`.
    var models: [ShimModel] = []

    /// The slug of the currently-active model, if any.
    var activeModel: String?

    /// Whether ChatGPT passthrough mode is available.
    var chatGPTPassthroughAvailable: Bool = false

    /// Resolved filesystem path to the `codex-shim` binary.
    var shimPath: String = ""

    /// Whether the shim binary was located on `$PATH` or auto-discovered.
    var shimFound: Bool = false

    /// The most recent tail of `shim.log` (up to 50 lines).
    var lastLogLines: [String] = []

    /// Diagnostic log from the last binary discovery run.
    var shimDiscoveryLog: String = ""

    /// Indicates an async operation is in flight.
    var isLoading: Bool = false

    /// Human-readable description of the last error, if any.
    var lastError: String?

    // MARK: - Sub-Managers

    /// Manages the on-disk `models.json` file.
    let modelsManager = ModelsJsonManager.shared

    /// Persistent user settings (polling interval, port, etc.).
    let settings = AppSettings.shared

    // MARK: - Private State

    /// Timer used for periodic status polling.
    private var pollingTimer: Timer?

    /// Cache variables for Codex app.asar modification tracking to avoid redundant disk I/O.
    private var lastCheckedAsarModDate: Date?
    private var lastCheckedAsarSize: UInt64?

    // MARK: - Initialization

    private init() {}

    // MARK: - Lifecycle

    /// Begin polling the shim's status at the interval defined in ``AppSettings/pollingInterval``.
    ///
    /// The timer fires on the main run loop so that UI updates happen on the
    /// correct actor. Each tick calls ``refreshStatus()`` in an unstructured task.
    func startPolling() {
        stopPolling()

        let interval = settings.pollingInterval
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshStatus()
            }
        }
        // Make sure the timer fires even when menus are open.
        RunLoop.main.add(pollingTimer!, forMode: .common)
    }

    /// Stop the status-polling timer.
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Bootstrap

    /// One-shot initializer called on app launch.
    ///
    /// Locates the `codex-shim` binary, loads persisted models, and performs
    /// an initial status check.
    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Locate the shim binary using multiple discovery strategies
        await discoverShimPath()

        // 2. Load models from models.json
        do {
            try modelsManager.load()
            models = modelsManager.models
        } catch {
            lastError = "Failed to load models.json: \(error.localizedDescription)"
        }

        // 3. Initial status refresh
        await refreshStatus()
    }

    /// Re-runs binary discovery and updates the shim path.
    /// Can be called from the UI when the user wants to re-detect the binary.
    func rediscoverShimPath() async {
        isLoading = true
        defer { isLoading = false }
        await discoverShimPath()
        await refreshStatus()
    }

    /// Multi-strategy binary discovery: persisted → which → mdfind → find → common paths.
    private func discoverShimPath() async {
        var log = [String]()

        // Strategy 1: Use the persisted path if it resolves to an actual executable.
        let persisted = settings.shimPath
        log.append("[1] Persisted path: '\(persisted)'")
        if persisted != "codex-shim" && !persisted.isEmpty {
            let exists = FileManager.default.fileExists(atPath: persisted)
            let exec   = FileManager.default.isExecutableFile(atPath: persisted)
            log.append("    exists=\(exists) executable=\(exec)")
            if exists {
                shimPath = persisted
                shimFound = true
                shimDiscoveryLog = log.joined(separator: "\n")
                return
            }
        }

        // Strategy 2: which (works if codex-shim is on PATH)
        if let path = await ProcessRunner.which("codex-shim") {
            let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
            log.append("[2] which found: '\(cleaned)'")
            if !cleaned.isEmpty && FileManager.default.fileExists(atPath: cleaned) {
                shimPath = cleaned
                shimFound = true
                settings.shimPath = cleaned
                shimDiscoveryLog = log.joined(separator: "\n")
                return
            }
        } else {
            log.append("[2] which: not found")
        }

        // Strategy 3: Spotlight / mdfind
        log.append("[3] Running mdfind...")
        if let spotlightPath = await autoDiscoverShimPath(log: &log) {
            shimPath = spotlightPath
            shimFound = true
            settings.shimPath = spotlightPath
            shimDiscoveryLog = log.joined(separator: "\n")
            return
        }

        // Strategy 4: `find` across home dir and Documents
        log.append("[4] Running find...")
        if let foundPath = await findShimWithFind(log: &log) {
            shimPath = foundPath
            shimFound = true
            settings.shimPath = foundPath
            shimDiscoveryLog = log.joined(separator: "\n")
            return
        }

        // Strategy 5: Check common known locations
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/codex-shim/bin/codex-shim",
            "\(home)/.local/bin/codex-shim",
            "/usr/local/bin/codex-shim",
            "/opt/homebrew/bin/codex-shim",
        ]
        for candidate in candidates {
            let exists = FileManager.default.fileExists(atPath: candidate)
            log.append("[5] Checking \(candidate): \(exists)")
            if exists {
                shimPath = candidate
                shimFound = true
                settings.shimPath = candidate
                shimDiscoveryLog = log.joined(separator: "\n")
                return
            }
        }

        // Not found
        log.append("[!] All strategies exhausted — not found")
        shimDiscoveryLog = log.joined(separator: "\n")
        shimPath = "codex-shim"
        shimFound = false
    }

    /// Auto-discovers the `codex-shim` binary location using Spotlight (mdfind).
    private func autoDiscoverShimPath(log: inout [String]) async -> String? {
        do {
            let result = try await ProcessRunner.run("/usr/bin/mdfind", arguments: ["-name", "codex-shim"])
            let paths = result.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            log.append("    mdfind returned \(paths.count) result(s): \(paths.prefix(3).joined(separator: ", "))")
            // Prefer paths inside a bin/ directory
            for path in paths where path.hasSuffix("/bin/codex-shim") {
                if FileManager.default.fileExists(atPath: path) {
                    log.append("    -> selected bin path: \(path)")
                    return path
                }
            }
            // Any matching file
            for path in paths {
                if FileManager.default.fileExists(atPath: path) {
                    log.append("    -> selected fallback path: \(path)")
                    return path
                }
            }
        } catch {
            log.append("    mdfind error: \(error)")
        }
        return nil
    }

    /// Uses `find` across targeted developer subdirectories as a last resort.
    private func findShimWithFind(log: inout [String]) async -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possibleSubdirs = [
            "\(home)/Developer",
            "\(home)/Projects",
            "\(home)/Downloads",
            "\(home)/Documents",
            "\(home)/codex-shim",
            "\(home)/.local"
        ]
        
        let searchRoots = possibleSubdirs.filter { FileManager.default.fileExists(atPath: $0) }
        guard !searchRoots.isEmpty else {
            log.append("    find: no candidate subdirectories found")
            return nil
        }
        
        do {
            var args = searchRoots
            args.append(contentsOf: [
                "-maxdepth", "6",
                "-name", "codex-shim",
                "(", "-type", "f", "-o", "-type", "l", ")"
            ])
            
            let result = try await ProcessRunner.run("/usr/bin/find", arguments: args)
            let paths = result.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            log.append("    find returned \(paths.count) result(s)")
            for path in paths where path.hasSuffix("/bin/codex-shim") {
                if FileManager.default.fileExists(atPath: path) {
                    log.append("    -> selected: \(path)")
                    return path
                }
            }
            for path in paths {
                if FileManager.default.fileExists(atPath: path) {
                    log.append("    -> selected: \(path)")
                    return path
                }
            }
        } catch {
            log.append("    find error: \(error)")
        }
        return nil
    }

    // MARK: - CLI Wrappers

    /// Checks if the Codex Desktop app is patched by looking for the needle/replacement in app.asar.
    /// Uses file metadata caching to avoid redundant byte scans.
    func checkCodexPatchedStatus() async {
        let appAsarPath = "/Applications/Codex.app/Contents/Resources/app.asar"
        guard FileManager.default.fileExists(atPath: appAsarPath) else {
            isCodexPatched = false
            lastCheckedAsarModDate = nil
            lastCheckedAsarSize = nil
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: appAsarPath)
            let modDate = attributes[.modificationDate] as? Date
            let size = attributes[.size] as? UInt64

            // If attributes haven't changed since last check, return cached value
            if let lastMod = lastCheckedAsarModDate,
               let lastSize = lastCheckedAsarSize,
               lastMod == modDate,
               lastSize == size {
                return
            }

            // Update modification attributes
            lastCheckedAsarModDate = modDate
            lastCheckedAsarSize = size

            // Read app.asar. Since it's large (159MB), we do this using safe options.
            let url = URL(fileURLWithPath: appAsarPath)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            
            // Search for the signature comment "codex-shim-patched" or the legacy replacement "let u=!1,d;"
            if let signature = "codex-shim-patched".data(using: .utf8),
               data.range(of: signature) != nil {
                isCodexPatched = true
            } else if let legacyReplacement = "let u=!1,d;".data(using: .utf8),
                      data.range(of: legacyReplacement) != nil {
                isCodexPatched = true
            } else {
                isCodexPatched = false
            }
        } catch {
            isCodexPatched = false
            lastCheckedAsarModDate = nil
            lastCheckedAsarSize = nil
        }
    }

    /// Query the shim process for its current status.
    ///
    /// Parses the text output of `codex-shim status` looking for keywords
    /// such as *running* or *stopped*, and extracts the active model count.
    func refreshStatus() async {
        await checkCodexPatchedStatus()
        await loadLogTail() // Load logs automatically on status ticks to share polling timer resource
        do {
            let result = try await ProcessRunner.runShim(
                "status",
                shimPath: settings.shimPath,
                port: settings.port
            )
            parseStatusOutput(result.stdout, exitCode: result.exitCode)
        } catch {
            // If the command itself fails, the shim is almost certainly not running.
            status = .stopped
            isEnabled = false
            activeModel = nil
        }
    }

    /// Generate the shim configuration files from `models.json`.
    func generate() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            _ = try await ProcessRunner.runShim(
                "generate",
                shimPath: settings.shimPath,
                port: settings.port
            )
        } catch {
            lastError = "Generate failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Start the shim process.
    func start() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            _ = try await ProcessRunner.runShim(
                "start",
                shimPath: settings.shimPath,
                port: settings.port
            )
            await refreshStatus()
        } catch {
            lastError = "Start failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Stop the shim process.
    func stop() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            _ = try await ProcessRunner.runShim(
                "stop",
                shimPath: settings.shimPath,
                port: settings.port
            )
            await refreshStatus()
        } catch {
            lastError = "Stop failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Enable the shim: start the process and install the proxy configuration.
    func enable() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        guard shimFound else {
            lastError = "codex-shim binary not found. Set the correct path in Settings → General."
            throw NSError(domain: "ShimManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: lastError!])
        }

        do {
            let result = try await ProcessRunner.runShim(
                "enable",
                shimPath: settings.shimPath,
                port: settings.port
            )
            if !result.succeeded {
                let detail = result.stderr.isEmpty ? result.stdout : result.stderr
                lastError = "Enable exited \(result.exitCode): \(detail.prefix(120))"
                throw NSError(domain: "ShimManager", code: Int(result.exitCode),
                              userInfo: [NSLocalizedDescriptionKey: lastError!])
            }
            isEnabled = true
            await refreshStatus()
        } catch {
            if lastError == nil { lastError = "Enable failed: \(error.localizedDescription)" }
            throw error
        }
    }

    /// Disable the shim: restore the original configuration and stop the process.
    func disable() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let result = try await ProcessRunner.runShim(
                "disable",
                shimPath: settings.shimPath,
                port: settings.port
            )
            if !result.succeeded {
                let detail = result.stderr.isEmpty ? result.stdout : result.stderr
                lastError = "Disable exited \(result.exitCode): \(detail.prefix(120))"
                throw NSError(domain: "ShimManager", code: Int(result.exitCode),
                              userInfo: [NSLocalizedDescriptionKey: lastError!])
            }
            isEnabled = false
            await refreshStatus()
        } catch {
            if lastError == nil { lastError = "Disable failed: \(error.localizedDescription)" }
            throw error
        }
    }

    /// Restart the shim process (stop + start).
    func restart() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            _ = try await ProcessRunner.runShim(
                "restart",
                shimPath: settings.shimPath,
                port: settings.port
            )
            await refreshStatus()
        } catch {
            lastError = "Restart failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Switch the active model to the one identified by `slug`.
    ///
    /// After switching, the configuration is regenerated so the shim picks up
    /// the new model on next request.
    /// - Parameter slug: The model slug to activate (e.g. `"gpt-4o"`).
    func switchModel(_ slug: String) async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            _ = try await ProcessRunner.runShim(
                "model",
                arguments: ["use", slug],
                shimPath: settings.shimPath,
                port: settings.port
            )
            activeModel = slug
            try await generate()
        } catch {
            lastError = "Switch model failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Apply the codex-shim patch to the Codex desktop app.
    ///
    /// The codesign re-signing step can fail with a non-zero exit code even
    /// when the ASAR patch was written successfully (e.g. on a fresh permissions
    /// grant). We always verify the actual ASAR content after the command runs,
    /// and only surface an error if the patch genuinely did not take effect.
    func patchApp() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let isAppWritable = FileManager.default.isWritableFile(atPath: "/Applications/Codex.app")
        let isAsarWritable = FileManager.default.isWritableFile(atPath: "/Applications/Codex.app/Contents/Resources/app.asar")
        let needsElevation = !isAppWritable || !isAsarWritable

        var cliError: Error?
        do {
            let result: ProcessResult
            if needsElevation {
                let args = ["--port", "\(settings.port)", "patch-app"]
                result = try await ProcessRunner.runElevated(settings.shimPath, arguments: args)
            } else {
                result = try await ProcessRunner.runShim(
                    "patch-app",
                    shimPath: settings.shimPath,
                    port: settings.port
                )
            }
            // If the CLI itself reported a clear failure before writing the patch, surface it.
            if !result.succeeded && result.stdout.contains("Could not find") {
                lastError = result.stderr.isEmpty ? result.stdout : result.stderr
                throw NSError(domain: "ShimManager", code: Int(result.exitCode),
                              userInfo: [NSLocalizedDescriptionKey: lastError!])
            }
        } catch {
            cliError = error
        }

        // Ground-truth check: did the ASAR actually get patched?
        await checkCodexPatchedStatus()

        if isCodexPatched {
            // Patch took effect — success regardless of codesign exit code.
            lastError = nil
        } else if let err = cliError {
            lastError = "Patch failed: \(err.localizedDescription)"
            throw err
        } else {
            lastError = "Patch did not take effect. Check that Codex Desktop is installed at /Applications/Codex.app."
            throw NSError(domain: "ShimManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: lastError!])
        }
    }

    /// Restore the Codex desktop app to its unpatched state.
    func restoreApp() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let isAppWritable = FileManager.default.isWritableFile(atPath: "/Applications/Codex.app")
        let isAsarWritable = FileManager.default.isWritableFile(atPath: "/Applications/Codex.app/Contents/Resources/app.asar")
        let needsElevation = !isAppWritable || !isAsarWritable

        var cliError: Error?
        do {
            if needsElevation {
                let args = ["--port", "\(settings.port)", "restore-app"]
                _ = try await ProcessRunner.runElevated(settings.shimPath, arguments: args)
            } else {
                _ = try await ProcessRunner.runShim(
                    "restore-app",
                    shimPath: settings.shimPath,
                    port: settings.port
                )
            }
        } catch {
            cliError = error
        }

        // Ground-truth check: is the ASAR now unpatched?
        await checkCodexPatchedStatus()

        if !isCodexPatched {
            // Restore took effect — success.
            lastError = nil
        } else if let err = cliError {
            lastError = "Restore failed: \(err.localizedDescription)"
            throw err
        } else {
            lastError = "Restore did not take effect."
            throw NSError(domain: "ShimManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: lastError!])
        }
    }

    /// Launch the Codex desktop application using native NSWorkspace or a non-blocking background process.
    func launchCodexApp() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        // 1. Try launching natively via LaunchServices (instant and non-blocking)
        if NSWorkspace.shared.launchApplication("Codex") {
            return
        }

        // 2. Fallback: run codex-shim app in the background so it doesn't block the UI thread
        let path = settings.shimPath
        let port = settings.port
        Task.detached(priority: .background) {
            _ = try? await ProcessRunner.runShim(
                "app",
                arguments: ["."],
                shimPath: path,
                port: port
            )
        }
    }

    // MARK: - File Operations

    /// Open `~/.codex-shim/models.json` in the user's default editor.
    func openModelsJson() {
        let modelsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-shim")
            .appendingPathComponent("models.json")

        NSWorkspace.shared.open(modelsPath)
    }

    /// Dynamic helper to resolve the exact log URL on disk based on installation path
    private var resolvedLogURL: URL {
        if shimFound && shimPath.contains("/") {
            let binaryURL = URL(fileURLWithPath: shimPath)
            let projectURL = binaryURL.deletingLastPathComponent().deletingLastPathComponent()
            let localLogURL = projectURL.appendingPathComponent(".codex-shim/shim.log")
            if FileManager.default.fileExists(atPath: localLogURL.path) {
                return localLogURL
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-shim")
            .appendingPathComponent("shim.log")
    }

    /// Open the shim log file (`shim.log`) in the user's default editor.
    func openShimLog() {
        NSWorkspace.shared.open(resolvedLogURL)
    }

    /// Load the last 50 lines of `shim.log` into ``lastLogLines``.
    func loadLogTail() async {
        let logURL = resolvedLogURL
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            lastLogLines = ["(shim.log not found)"]
            return
        }

        do {
            let content = try String(contentsOf: logURL, encoding: .utf8)
            let allLines = content.components(separatedBy: .newlines)
            lastLogLines = Array(allLines.suffix(50))
        } catch {
            lastLogLines = ["(Failed to read shim.log: \(error.localizedDescription))"]
        }
    }

    // MARK: - Provider Management

    /// Add a new provider and its selected models to the configuration.
    ///
    /// Saves the API key to the Keychain, writes model definitions to
    /// `models.json`, regenerates the shim config, and restarts the process
    /// if it was already running.
    ///
    /// - Parameters:
    ///   - provider: The provider definition describing the new backend.
    ///   - selectedModels: The subset of models the user chose to enable.
    ///   - apiKey: The provider's API key to store securely.
    func addProvider(
        provider: ProviderDefinition,
        selectedModels: [ProviderModelDef],
        apiKey: String
    ) async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            // 1. Persist the API key in the Keychain.
            try KeychainManager.saveKey(apiKey, forProvider: provider.id)

            // 2. Merge the selected models into models.json.
            try modelsManager.addModels(
                for: provider,
                selectedModels: selectedModels,
                apiKey: apiKey
            )
            models = modelsManager.models

            // 3. Regenerate shim config from the updated models list.
            try await generate()

            // 4. If the shim is currently running, restart to pick up changes.
            if status == .running {
                try await restart()
            } else {
                await refreshStatus()
            }
        } catch {
            lastError = "Add provider failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Remove a provider and all its associated models.
    ///
    /// - Parameter providerId: Unique identifier of the provider to remove.
    func removeProvider(_ providerId: String) async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            // Remove models associated with this provider.
            try modelsManager.removeProvider(providerId)
            models = modelsManager.models

            // Regenerate shim config.
            try await generate()

            // Restart if running so the old provider is no longer served.
            if status == .running {
                try await restart()
            } else {
                await refreshStatus()
            }
        } catch {
            lastError = "Remove provider failed: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Parse the text output from `codex-shim status` and update published state.
    ///
    /// Expected output patterns:
    /// - "Status: running" / "Status: stopped"
    /// - "Active model: gpt-4o"
    /// - "Models: 5"
    /// - "Enabled: true/false"
    /// Parse the text output and exit code from `codex-shim status` and update published state.
    private func parseStatusOutput(_ output: String, exitCode: Int32) {
        let lowered = output.lowercased()

        // 1. If command reported non-zero status exit code, it's typically stopped or not configured.
        if exitCode != 0 {
            status = .stopped
            isEnabled = false
            activeModel = nil
            return
        }

        // 2. Determine running state with robust string keyword matching
        if lowered.contains("running") || lowered.contains("active") || lowered.contains("started") || lowered.contains("online") {
            status = .running
            isEnabled = true
        } else if lowered.contains("stopped") || lowered.contains("not running") || lowered.contains("offline") || lowered.contains("inactive") {
            status = .stopped
            isEnabled = false
            activeModel = nil
        } else {
            // Fallback: if exit code is 0 but keywords are absent, assume running if stdout is present
            if !output.isEmpty {
                status = .running
                isEnabled = true
            } else {
                status = .unknown
                isEnabled = false
            }
        }

        // Extract active model
        if let modelLine = output.components(separatedBy: .newlines)
            .first(where: { $0.lowercased().hasPrefix("active model") }) {
            let parts = modelLine.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let model = parts[1].trimmingCharacters(in: .whitespaces)
                activeModel = model.isEmpty ? nil : model
            }
        }

        // Check ChatGPT passthrough availability
        chatGPTPassthroughAvailable = lowered.contains("passthrough")
    }
}
