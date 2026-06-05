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

    /// Whether Cursor/Composer passthrough mode is available.
    var cursorPassthroughAvailable: Bool = false

    /// Whether the Auto Router is configured and active.
    var autoRouterEnabled: Bool = false

    /// Live model list fetched from `/v1/models`, reflecting what the running shim actually serves.
    var liveModels: [LiveModel] = []

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

    /// Output lines from a running CLI task (codex-shim codex --).
    var cliTaskOutput: [String] = []

    /// Whether a CLI task is currently running.
    var isCliTaskRunning: Bool = false

    // MARK: - Sub-Managers

    /// Manages the on-disk `models.json` file.
    let modelsManager = ModelsJsonManager.shared

    /// Manages syncing models to Zencoder's settings.json file.
    let zencoderManager = ZencoderSettingsManager.shared

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

        LegacyShimMigration.run()

        // 1. Locate the shim binary using multiple discovery strategies
        await discoverShimPath()

        // 2. Load models from models.json
        do {
            try modelsManager.load()
            models = modelsManager.models
        } catch {
            lastError = "Failed to load models.json: \(error.localizedDescription)"
        }

        // 3. Ensure auto-router entry is in catalog
        injectAutoRouterIntoCatalog()

        // 4. Initial status refresh
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

    private func shimArgs(_ subcommand: String, extra: [String] = []) throws -> [String] {
        guard shimFound else {
            throw NSError(domain: "ShimManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "codex-shim binary not found. Set the correct path in Settings → General."])
        }
        var args = ["--port", "\(settings.port)"]
        if let sp = settings.settingsPath, !sp.isEmpty {
            args += ["--settings", sp]
        }
        args.append(subcommand)
        args.append(contentsOf: extra)
        return args
    }

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

            if let lastMod = lastCheckedAsarModDate,
               let lastSize = lastCheckedAsarSize,
               lastMod == modDate,
               lastSize == size {
                return
            }

            lastCheckedAsarModDate = modDate
            lastCheckedAsarSize = size

            isCodexPatched = searchFile(atPath: appAsarPath, for: [
                "codex-shim-patched".data(using: .utf8)!,
                "let u=!1,d;".data(using: .utf8)!
            ])
        } catch {
            isCodexPatched = false
            lastCheckedAsarModDate = nil
            lastCheckedAsarSize = nil
        }
    }

    private func searchFile(atPath path: String, for needles: [Data]) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return false
        }
        defer { try? handle.close() }

        let chunkSize = 1024 * 1024
        let maxOverlap = needles.map(\.count).max() ?? 0
        var buffer = Data()

        while true {
            let chunk = try? handle.read(upToCount: chunkSize)
            guard let chunk, !chunk.isEmpty else { break }

            buffer.append(chunk)

            for needle in needles {
                if buffer.range(of: needle) != nil {
                    return true
                }
            }

            if buffer.count > maxOverlap {
                buffer = Data(buffer.suffix(maxOverlap))
            }
        }

        for needle in needles {
            if buffer.range(of: needle) != nil {
                return true
            }
        }

        return false
    }

    /// Query the shim process for its current status via the `/health` HTTP API.
    ///
    /// Sends a GET request to `http://127.0.0.1:{port}/health` and parses the
    /// structured JSON response `{ok, models, chatgpt_passthrough, cursor_passthrough, auto_router}`.
    /// Falls back to `.stopped` when the shim is unreachable.
    func refreshStatus() async {
        await checkCodexPatchedStatus()
        await loadLogTail()

        let url = URL(string: "http://127.0.0.1:\(settings.port)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                applyStoppedState()
                return
            }

            let health = try JSONDecoder().decode(HealthResponse.self, from: data)

            if health.ok {
                status = .running
                isEnabled = true
            } else {
                status = .stopped
                isEnabled = false
                activeModel = nil
            }

            chatGPTPassthroughAvailable = health.chatgptPassthrough
            cursorPassthroughAvailable = health.cursorPassthrough
            autoRouterEnabled = health.autoRouter || (modelsManager.routerConfig?.enabled ?? false)

            await fetchLiveModels()
        } catch {
            applyStoppedState()
        }
    }

    private func applyStoppedState() {
        status = .stopped
        isEnabled = false
        activeModel = nil
        chatGPTPassthroughAvailable = false
        cursorPassthroughAvailable = false
        autoRouterEnabled = modelsManager.routerConfig?.enabled ?? false
    }

    /// Fetch the live model list from the running shim's `/v1/models` endpoint.
    func fetchLiveModels() async {
        guard status == .running else {
            liveModels = []
            return
        }

        liveModels = ShimServer.shared.snapshot.models
    }

    /// Generate the shim configuration files from `models.json`.
    func generate() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let args = try shimArgs("generate")
            _ = try await ProcessRunner.run(settings.shimPath, arguments: args)
            injectAutoRouterIntoCatalog()
        } catch {
            lastError = "Generate failed: \(error.localizedDescription)"
            throw error
        }
    }

    private func injectAutoRouterIntoCatalog() {
        let router = modelsManager.routerConfig
        let routerEnabled = router?.enabled ?? false
        let routerSlug = router?.slug ?? "codex-auto"

        let fm = FileManager.default
        let catalogURL = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-shim/custom_model_catalog.json")

        guard fm.fileExists(atPath: catalogURL.path) else { return }

        do {
            let data = try Data(contentsOf: catalogURL)
            var catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            var models = catalog["models"] as? [[String: Any]] ?? []

            let existingIdx = models.firstIndex { ($0["slug"] as? String) == routerSlug }

            if !routerEnabled {
                if let idx = existingIdx {
                    models.remove(at: idx)
                    catalog["models"] = models
                    let updated = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
                    try updated.write(to: catalogURL, options: .atomic)
                }
                return
            }

            guard let router else { return }

            if existingIdx == nil {
                let entry: [String: Any] = [
                    "slug": router.slug,
                    "display_name": router.displayName,
                    "description": "Auto router – classifies each task and routes to the best candidate model.",
                    "context_window": 128000,
                    "max_context_window": 128000,
                    "auto_compact_token_limit": 102400,
                    "truncation_policy": ["mode": "tokens", "limit": 40960],
                    "default_reasoning_level": "medium",
                    "supported_reasoning_levels": [
                        ["effort": "low", "description": "Faster, lighter reasoning"],
                        ["effort": "medium", "description": "Balanced speed and reasoning"],
                        ["effort": "high", "description": "Deeper reasoning"],
                        ["effort": "xhigh", "description": "Maximum reasoning where supported"]
                    ],
                    "default_reasoning_summary": "none",
                    "supports_reasoning_summaries": false,
                    "default_verbosity": "low",
                    "support_verbosity": false,
                    "apply_patch_tool_type": "freeform",
                    "web_search_tool_type": "text_and_image",
                    "supports_search_tool": false,
                    "supports_parallel_tool_calls": true,
                    "experimental_supported_tools": [],
                    "input_modalities": ["text", "image"],
                    "supports_image_detail_original": true,
                    "shell_type": "shell_command",
                    "visibility": "list",
                    "minimal_client_version": "0.0.1",
                    "supported_in_api": true,
                    "availability_nux": NSNull(),
                    "upgrade": NSNull(),
                    "priority": 2000,
                    "prefer_websockets": false,
                    "available_in_plans": ["free", "plus", "pro", "team", "business", "enterprise"],
                    "base_instructions": "You are a coding agent running in Codex through a local BYOK shim with smart auto-routing.",
                    "model_messages": [
                        "instructions_template": "You are Codex running through a smart auto-router that picks the best model for each task. Be a helpful, direct coding collaborator.",
                        "instructions_variables": ["model_name": router.displayName]
                    ]
                ]
                models.append(entry)
                catalog["models"] = models

                let updated = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
                try updated.write(to: catalogURL, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: catalogURL.path)
            }
        } catch {
            DebugLogger.log("injectAutoRouterIntoCatalog: failed: \(error)")
        }
    }

    /// Start the shim process.
    func start() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            try await ShimServer.shared.start()
            injectAutoRouterIntoCatalog()
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

        try await ShimServer.shared.stop()
        await refreshStatus()
    }

    /// Enable the shim: start the process and install the proxy configuration.
    func enable() async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let args = try shimArgs("enable")
        do {
            let result = try await ProcessRunner.run(settings.shimPath, arguments: args)
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

        let args = try shimArgs("disable")
        do {
            let result = try await ProcessRunner.run(settings.shimPath, arguments: args)
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

        try await ShimServer.shared.restart()
        injectAutoRouterIntoCatalog()
        await refreshStatus()
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
            let args = try shimArgs("model", extra: ["use", slug])
            _ = try await ProcessRunner.run(settings.shimPath, arguments: args)
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
                let args = try shimArgs("patch-app")
                result = try await ProcessRunner.run(settings.shimPath, arguments: args)
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
                let args = try shimArgs("restore-app")
                _ = try await ProcessRunner.run(settings.shimPath, arguments: args)
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

        if NSWorkspace.shared.launchApplication("Codex") {
            return
        }

        let args = (try? shimArgs("app", extra: ["."])) ?? ["--port", "\(settings.port)", "app", "."]
        let path = settings.shimPath
        Task.detached(priority: .background) {
            _ = try? await ProcessRunner.run(path, arguments: args)
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

    /// Classify a Zenflow task by sending a prompt to the shim's `/v1/chat/completions` endpoint.
    ///
    /// - Parameters:
    ///   - prompt: The classification prompt to send.
    ///   - model: The model slug to use for classification.
    /// - Returns: The classifier's content string on 2xx, `nil` otherwise.
    func callClassifier(prompt: String, model: String) async -> String? {
        let url = URL(string: "http://127.0.0.1:\(settings.port)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: prompt)],
            temperature: 0.0,
            maxTokens: 64
        )

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            DebugLogger.log("ShimManager: callClassifier failed: \(error)")
            return nil
        }
    }

    /// Run a one-off Codex CLI task via `codex-shim codex -- <args>`.
    ///
    /// Streams output line-by-line into `cliTaskOutput`.
    func runCodexTask(prompt: String) async {
        isCliTaskRunning = true
        cliTaskOutput = []
        lastError = nil
        defer { isCliTaskRunning = false }

        do {
            let args = try shimArgs("codex", extra: ["--", prompt])
            let result = try await ProcessRunner.run(settings.shimPath, arguments: args)

            let lines = result.stdout
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
            cliTaskOutput = lines

            if !result.succeeded {
                let errLines = result.stderr.components(separatedBy: .newlines).filter { !$0.isEmpty }
                cliTaskOutput.append(contentsOf: errLines)
                lastError = "CLI task exited with code \(result.exitCode)"
            }
        } catch {
            lastError = "CLI task failed: \(error.localizedDescription)"
            cliTaskOutput = [lastError!]
        }
    }

    /// Load the last 50 lines of `shim.log` into ``lastLogLines``.
    func loadLogTail() async {
        let logURL = resolvedLogURL
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            lastLogLines = ["(shim.log not found)"]
            return
        }

        do {
            let handle = try FileHandle(forReadingFrom: logURL)
            let fileSize = try handle.seekToEnd()
            let readSize = min(fileSize, 8192)
            try handle.seek(toOffset: fileSize - readSize)
            let data = try handle.readToEnd() ?? Data()
            try? handle.close()

            let content = String(data: data, encoding: .utf8) ?? ""
            let allLines = content.components(separatedBy: .newlines)
            let tail = Array(allLines.suffix(50))
            lastLogLines = tail.isEmpty ? ["(empty log)"] : tail
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

    /// Convenience method that runs the full Zenflow auto router flow:
    /// routes the task using the classifier if available, falling back to default.
    func routeZenflowTask(
        taskTitle: String,
        taskDescription: String,
        projectPath: String
    ) async -> String {
        let classifierAvailable = status == .running && autoRouterEnabled

        return await ZenflowRouterManager.shared.routeFully(
            taskTitle: taskTitle,
            taskDescription: taskDescription,
            projectPath: projectPath,
            classifierAvailable: classifierAvailable,
            callClassifier: { model, prompt in
                await self.callClassifier(prompt: prompt, model: model)
            }
        )
    }

}
