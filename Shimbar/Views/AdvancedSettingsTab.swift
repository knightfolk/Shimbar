// MARK: - AdvancedSettingsTab.swift
// Shimbar – Advanced developer options and log viewer
// macOS 14+

import SwiftUI

struct AdvancedSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    @State private var disablePassthrough: Bool = AppSettings.shared.disableChatGPTPassthrough
    @State private var logTimer: Timer? = nil
    
    var body: some View {
        Form {
            Section {
                // ChatGPT Passthrough Toggle
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
                        Text("When enabled, codex-shim routes default ChatGPT models directly to their respective API hosts rather than attempting web proxying.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            } header: {
                Text("Compatibilities")
                    .font(.headline)
            }
            .padding(.bottom, 12)
            
            Section {
                // Patch / Restore Codex App
                HStack(spacing: 12) {
                    Button("Patch Codex Desktop") {
                        Task {
                            try? await manager.patchApp()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Restore Original App") {
                        Task {
                            try? await manager.restoreApp()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                
                Text("Modifies the Codex Desktop electron application bundle to point its API requests to Shimbar's local proxy port. Easy to revert anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Application Patching")
                    .font(.headline)
            }
            .padding(.bottom, 12)
            
            Section {
                // Monospaced Log Viewer
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Live Log Stream")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear Stored Keychains") {
                            resetAllKeys()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
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
                            .padding(8)
                        }
                        .frame(height: 180)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.1)))
                        .onChange(of: manager.lastLogLines) { _, newValue in
                            if !newValue.isEmpty {
                                proxy.scrollTo(newValue.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            } header: {
                Text("Diagnostics")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            disablePassthrough = AppSettings.shared.disableChatGPTPassthrough
            startLogPolling()
        }
        .onDisappear {
            stopLogPolling()
        }
    }
    
    private func startLogPolling() {
        Task {
            await manager.loadLogTail()
        }
        logTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await manager.loadLogTail()
            }
        }
    }
    
    private func stopLogPolling() {
        logTimer?.invalidate()
        logTimer = nil
    }
    
    private func resetAllKeys() {
        let providers = KeychainManager.storedProviderIds()
        for p in providers {
            try? KeychainManager.deleteKey(forProvider: p)
        }
    }
}
