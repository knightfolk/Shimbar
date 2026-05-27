// MARK: - AdvancedSettingsTab.swift
// Shimbar – Advanced developer options and log viewer
// macOS 14+

import SwiftUI

struct AdvancedSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    @State private var disablePassthrough: Bool = AppSettings.shared.disableChatGPTPassthrough
    @State private var showingWipeAlert = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
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
                
                // --- SECTION 2: Diagnostics ---
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
            Task {
                await manager.loadLogTail()
            }
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
    
    private func resetAllKeys() {
        let providers = KeychainManager.storedProviderIds()
        for p in providers {
            try? KeychainManager.deleteKey(forProvider: p)
        }
    }
}

