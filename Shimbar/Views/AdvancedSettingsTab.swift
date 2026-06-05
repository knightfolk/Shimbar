// MARK: - AdvancedSettingsTab.swift
// Shimbar – Advanced developer options and log viewer
// macOS 14+

import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    @Environment(ShimServer.self) private var server
    @State private var disablePassthrough: Bool = AppSettings.shared.disableChatGPTPassthrough
    @State private var showingWipeAlert = false
    @State private var customSettingsPath: String = AppSettings.shared.settingsPath ?? ""
    @State private var showFilePicker = false
    @State private var taskPrompt: String = ""
    @State private var testPromptResponse: String? = nil
    @State private var isSendingTestPrompt: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // --- SECTION 0: Config File ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("Config File")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Default: ~/.codex-shim/models.json", text: $customSettingsPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.title = "Select Config File"
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                panel.allowsMultipleSelection = false
                                panel.allowedContentTypes = [.json]
                                if panel.runModal() == .OK, let url = panel.urls.first {
                                    customSettingsPath = url.path
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            if !customSettingsPath.isEmpty {
                                Button("Reset") {
                                    customSettingsPath = ""
                                    AppSettings.shared.settingsPath = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        Text("When set, passes `--settings <path>` to all codex-shim CLI calls. Useful for managing multiple configurations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }

                // --- SECTION 1: Compatibilities ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("Compatibilities")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { disablePassthrough },
                            set: { newValue in
                                AppSettings.shared.disableChatGPTPassthrough = newValue
                                disablePassthrough = newValue
                                Task {
                                    try? await manager.generate()
                                    if manager.status.isRunning {
                                        try? await manager.restart()
                                    }
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Disable ChatGPT Web Passthrough")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("When enabled, codex-shim routes default ChatGPT models directly to their respective API hosts rather than attempting web proxying.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }

                // --- SECTION 2: Send Test Prompt ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("Send Test Prompt")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Enter a test prompt…", text: $taskPrompt, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .disabled(isSendingTestPrompt)
                            Button(isSendingTestPrompt ? "Sending…" : "Send") {
                                sendTestPrompt()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingTestPrompt)
                        }

                        if let response = testPromptResponse {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(response)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .frame(height: 120)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor).opacity(0.8)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                        }

                        Text("Sends a test prompt through the native ShimServer to verify the in-process server is working.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }

                // --- SECTION 3: Diagnostics ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("Diagnostics")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Live Log Stream")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Button("Clear Stored Credentials") {
                                    showingWipeAlert = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if manager.lastLogLines.isEmpty {
                                            Text("No log messages recorded. Make sure the daemon is running.")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .padding()
                                        } else {
                                            ForEach(0..<manager.lastLogLines.count, id: \.self) { index in
                                                Text(manager.lastLogLines[index])
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                                    .tag(index)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                }
                                .frame(height: 180)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor).opacity(0.8)))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                                .onChange(of: manager.lastLogLines) { _, newValue in
                                    if !newValue.isEmpty {
                                        proxy.scrollTo(newValue.count - 1, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }
                
                Spacer() // Pushes everything up to keep sections packed and prevent vertical stretching
            }
            .padding(20)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            disablePassthrough = AppSettings.shared.disableChatGPTPassthrough
            customSettingsPath = AppSettings.shared.settingsPath ?? ""
            Task {
                await manager.loadLogTail()
            }
        }
        .onChange(of: customSettingsPath) { _, newValue in
            AppSettings.shared.settingsPath = newValue.isEmpty ? nil : newValue
        }
        .alert("Are you sure you want to clear all stored API keys?", isPresented: $showingWipeAlert) {
            Button("Clear All Keys", role: .destructive) {
                resetAllKeys()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone and will permanently delete all API credentials from the Keychain.")
        }
    }
    
    private func sendTestPrompt() {
        isSendingTestPrompt = true
        testPromptResponse = nil
        Task {
            let model = manager.activeModel ?? manager.models.first?.slug ?? "gpt-4o"
            let result = await server.sendTestPrompt(taskPrompt, model: model)
            await MainActor.run {
                isSendingTestPrompt = false
                testPromptResponse = result ?? "(no response — server may not be running)"
            }
        }
    }

    private func resetAllKeys() {
        let providers = KeychainManager.storedProviderIds()
        for p in providers {
            try? KeychainManager.deleteKey(forProvider: p)
        }
    }
}

