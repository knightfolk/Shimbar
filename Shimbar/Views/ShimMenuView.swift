import SwiftUI

// MARK: - ShimMenuView

/// The primary view shown in the menu bar popover.
///
/// Displays daemon status, model selection, quick actions, and access
/// to settings. This is the main surface users interact with.
struct ShimMenuView: View {

    @Environment(ShimManager.self) private var manager
    @Environment(\.openSettings) private var openSettings
    @State private var isAutoSetupRunning = false
    @State private var autoSetupMessage: String? = nil
    @State private var isPatching = false
    @State private var isUpdatingShim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 12)
            // Show setup assistant banner when binary isn't found
            if !manager.shimFound {
                setupBanner
                Divider().padding(.horizontal, 12)
            }
            // Show update banner when upstream has new commits
            if manager.updater.updateAvailable && !manager.updater.isDismissed {
                updateBanner
                Divider().padding(.horizontal, 12)
            }
            configSection
            Divider().padding(.horizontal, 12)
            toggleSection
            Divider().padding(.horizontal, 12)
            modelSection
            Divider().padding(.horizontal, 12)
            providerSection
            Divider().padding(.horizontal, 12)
            actionsSection
            Divider().padding(.horizontal, 12)
            launchSection
            Divider().padding(.horizontal, 12)
            footerSection
            Divider().padding(.horizontal, 12)
            creditSection
        }
        .frame(width: 320)
        .padding(.vertical, 8)
    }

    // MARK: - Setup Assistant Banner

    /// Shown when codex-shim cannot be located. Guides the user through
    /// one-tap automatic discovery without needing to open Settings.
    private var setupBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.orange)
                Text("Setup Required")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Spacer()
            }

            Text("Shimbar can't locate codex-shim. Tap Auto-Detect or Browse to find it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let msg = autoSetupMessage {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(manager.shimFound ? Color.green : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Show discovery diagnostic log on failure
            if !manager.shimDiscoveryLog.isEmpty && !manager.shimFound && autoSetupMessage != nil {
                ScrollView {
                    Text(manager.shimDiscoveryLog)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 60)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.08)))
            }

            HStack(spacing: 8) {
                // Primary: Auto-detect
                Button(action: runAutoSetup) {
                    HStack(spacing: 6) {
                        if isAutoSetupRunning {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "magnifyingglass").font(.system(size: 11))
                        }
                        Text(isAutoSetupRunning ? "Searching…" : "Auto-Detect")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAutoSetupRunning)

                // Secondary: Browse for file
                Button(action: browseForShim) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder").font(.system(size: 11))
                        Text("Browse…").font(.system(size: 12))
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .disabled(isAutoSetupRunning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.07))
                .padding(.horizontal, 6)
        )
    }

    private func runAutoSetup() {
        isAutoSetupRunning = true
        autoSetupMessage = nil
        Task {
            await manager.rediscoverShimPath()
            await MainActor.run {
                isAutoSetupRunning = false
                if manager.shimFound {
                    autoSetupMessage = "✓ Found at \(manager.shimPath)"
                } else {
                    autoSetupMessage = "Not found automatically — try Browse to locate it manually."
                }
            }
        }
    }

    private func browseForShim() {
        let panel = NSOpenPanel()
        panel.title = "Locate codex-shim"
        panel.message = "Select the codex-shim executable file."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            manager.settings.shimPath = path
            Task {
                await manager.rediscoverShimPath()
                await MainActor.run {
                    if manager.shimFound {
                        autoSetupMessage = "✓ Set to \(path)"
                    } else {
                        autoSetupMessage = "File selected but may not be executable: \(path)"
                    }
                }
            }
        }
    }

    // MARK: - Update Banner

    /// Shown when the upstream codex-shim repository has newer commits
    /// than the locally installed version.
    private var updateBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.blue)
                Text("Update Available")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.blue)
                Spacer()
                Button(action: { manager.updater.isDismissed = true }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                Text("Local:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(manager.updater.localCommitHash ?? "???")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("→")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Remote:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(manager.updater.remoteCommitHash ?? "???")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            if let err = manager.updater.lastUpdateError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: runShimUpdate) {
                HStack(spacing: 6) {
                    if isUpdatingShim {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.down.circle").font(.system(size: 11))
                    }
                    Text(isUpdatingShim ? "Updating…" : "Update Now")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUpdatingShim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.07))
                .padding(.horizontal, 6)
        )
    }

    private func runShimUpdate() {
        isUpdatingShim = true
        Task {
            await manager.updater.performUpdate(shimManager: manager)
            await MainActor.run {
                isUpdatingShim = false
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("Shimbar")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(manager.status.iconColor)
                .frame(width: 8, height: 8)

            Text(manager.status.displayText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Current Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label("Codex status:", systemImage: "app.badge.checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Text(manager.isCodexPatched ? "patched" : "unpatched")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(manager.isCodexPatched ? Color.green : Color.red)
                
                Spacer()
                
                if isPatching {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                
                Toggle("", isOn: Binding(
                    get: { manager.isCodexPatched },
                    set: { newValue in
                        isPatching = true
                        Task {
                            do {
                                if newValue {
                                    try await manager.patchApp()
                                } else {
                                    try await manager.restoreApp()
                                }
                            } catch {
                                // Error is shown in the inline error row below
                            }
                            await manager.checkCodexPatchedStatus()
                            isPatching = false
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(isPatching)
            }
            
            // Show patch/unpatch errors right underneath if they happen
            if let err = manager.lastError, (err.contains("Patch") || err.contains("Restore") || err.contains("asar") || err.contains("permission") || err.contains("effect")) {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: { manager.lastError = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.alternatingContentBackgroundColors[0]).opacity(0.4))
                .padding(.horizontal, 6)
        )
    }

    // MARK: - Enable/Disable Toggle

    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Label("Shim Daemon", systemImage: "power")
                    .font(.system(size: 13))

                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("Turn on/off the local proxy daemon and system-level configuration hooks.")

                Spacer()

                if manager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Toggle("", isOn: Binding(
                        get: { manager.isEnabled },
                        set: { newValue in
                            Task {
                                do {
                                    if newValue { try await manager.enable() }
                                    else { try await manager.disable() }
                                } catch {
                                    // Error shown in the error row below
                                }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(!manager.shimFound)
                }
            }

            // Show binary-not-found warning inline
            if !manager.shimFound {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("codex-shim not found — open Settings → General to set path")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }

            // Show last command error inline (cleared on next action)
            if let err = manager.lastError, !err.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                    Spacer()
                    Button(action: { manager.lastError = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Model List

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("Active Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help(manager.isCodexPatched ? "Model selection is managed inside the patched Codex Desktop app picker." : "Lists configured models. Swap models here or roll this section up if you use the Codex dropdown patch.")

                if manager.autoRouterEnabled {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text("Router")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange.opacity(0.15)))
                }

                if manager.cursorPassthroughAvailable {
                    if !manager.autoRouterEnabled {
                        Spacer()
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "cursorarrow.and.square.3d")
                            .font(.system(size: 9))
                        Text("Composer")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.purple.opacity(0.15)))
                }

                if manager.isCodexPatched {
                    Spacer()
                    
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Controlled by Codex app")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if manager.settings.collapseModelSection, let activeModel = manager.activeModel {
                        Text("(\(activeModel))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.leading, 4)
                    }
                    
                    Spacer()

                    // Collapse/Expand toggle button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            manager.settings.collapseModelSection.toggle()
                        }
                    }) {
                        Image(systemName: manager.settings.collapseModelSection ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if !manager.isCodexPatched && !manager.settings.collapseModelSection {
                if manager.models.isEmpty {
                    Text("No models configured")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        if manager.autoRouterEnabled, let router = manager.modelsManager.routerConfig {
                            ModelListRow(
                                model: ShimModel(
                                    slug: router.slug,
                                    model: router.slug,
                                    displayName: router.displayName,
                                    provider: "codex-shim-auto",
                                    baseUrl: ""
                                ),
                                isActive: manager.activeModel == router.slug,
                                onSelect: { Task { try? await manager.switchModel(router.slug) } }
                            )
                        }
                        ForEach(manager.models, id: \.slug) { model in
                            ModelListRow(
                                model: model,
                                isActive: manager.activeModel == model.slug,
                                onSelect: { Task { try? await manager.switchModel(model.slug) } }
                            )
                        }

                        let chatGPTModels = manager.liveModels.filter { $0.isChatGPTPassthrough }
                        if !chatGPTModels.isEmpty && !manager.settings.disableChatGPTPassthrough {
                            ForEach(chatGPTModels) { lm in
                                ModelListRow(
                                    model: ShimModel(
                                        slug: lm.id,
                                        model: lm.id,
                                        displayName: "\(lm.id) (ChatGPT)",
                                        provider: "chatgpt",
                                        baseUrl: ""
                                    ),
                                    isActive: manager.activeModel == lm.id,
                                    onSelect: { Task { try? await manager.switchModel(lm.id) } }
                                )
                            }
                        }

                        let cursorModels = manager.liveModels.filter { $0.isCursorPassthrough }
                        if !cursorModels.isEmpty {
                            ForEach(cursorModels) { lm in
                                ModelListRow(
                                    model: ShimModel(
                                        slug: lm.id,
                                        model: lm.id,
                                        displayName: "\(lm.id) (Cursor)",
                                        provider: "cursor",
                                        baseUrl: ""
                                    ),
                                    isActive: manager.activeModel == lm.id,
                                    onSelect: { Task { try? await manager.switchModel(lm.id) } }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Add Provider

    private var providerSection: some View {
        MenuRow(
            title: "Add Provider…",
            icon: "plus.circle",
            helpText: "Launch the step-by-step setup wizard to configure API keys and models for a new LLM provider.",
            action: { ProviderSetupWindowManager.shared.show(manager: manager) }
        )
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 0) {
            MenuRow(
                title: "Restart Shim",
                icon: "arrow.clockwise",
                helpText: "Restart the local proxy process to reload settings or flush active connections.",
                action: { Task { try? await manager.restart() } }
            )

            MenuRow(
                title: "Sync to Zencoder",
                icon: "wand.and.stars",
                helpText: "Push all configured custom models to Zencoder's settings.json.",
                action: { ZencoderSettingsManager.shared.syncFromShimbar(forceAll: true) }
            )

            MenuRow(
                title: "View Log",
                icon: "doc.text",
                helpText: "Open the real-time background log file in your system's default editor for diagnostics.",
                action: { manager.openShimLog() }
            )

            MenuRow(
                title: "Diagnostics & Onboarding…",
                icon: "checklist",
                helpText: "Run environment checks, grant permissions, and configure dependencies.",
                action: { OnboardingWindowManager.shared.show(manager: manager) }
            )

        }
    }

    // MARK: - Launch Codex

    private var launchSection: some View {
        MenuRow(
            title: "Launch Codex Desktop",
            icon: "arrow.up.forward.app",
            isProminent: true,
            helpText: "Open the Codex Desktop application main user interface screen.",
            action: { Task { try? await manager.launchCodexApp() } }
        )
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 0) {
            MenuRow(
                title: "Settings…",
                icon: "gear",
                shortcut: "⌘,",
                expand: false,
                helpText: "Open the tabbed advanced preferences window for ports, paths, and custom environment settings.",
                action: { openSettingsWindow() }
            )

            Spacer()

            MenuRow(
                title: "Quit",
                icon: "xmark.circle",
                shortcut: "⌘Q",
                expand: false,
                helpText: "Quit the Shimbar menu bar utility application.",
                action: { NSApplication.shared.terminate(nil) }
            )
        }
        .padding(.horizontal, 0)
    }

    // MARK: - Helpers

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var creditSection: some View {
        HStack {
            Spacer()
            Text("Powered by")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Button(action: {
                if let url = URL(string: "https://github.com/0xSero/codex-shim") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("codex-shim")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - MenuRow

/// A reusable row used throughout the menu popover for action items.
struct MenuRow: View {

    let title: String
    let icon: String
    var isProminent: Bool = false
    var shortcut: String? = nil
    var expand: Bool = true
    var helpText: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isProminent ? Color.accentColor : Color.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: isProminent ? .medium : .regular))

                if let helpText {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .help(helpText)
                }

                if expand {
                    Spacer()
                }

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, expand ? 0 : 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : .clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
