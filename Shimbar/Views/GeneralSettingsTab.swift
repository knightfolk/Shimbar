// MARK: - GeneralSettingsTab.swift
// Shimbar – General application settings
// macOS 14+

import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    @State private var launchAtLogin: Bool = LoginItemManager.isEnabled
    
    // Bindings to AppSettings with local state wrappers for clean input validation
    @State private var portString: String = ""
    @State private var shimPathString: String = ""
    @State private var pollingSeconds: Double = 5.0
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // --- SECTION 1: System Options ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("System Options")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                do {
                                    try LoginItemManager.setEnabled(newValue)
                                    launchAtLogin = newValue
                                } catch {
                                    errorMessage = error.localizedDescription
                                    showingErrorAlert = true
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start Shimbar on System Launch")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Automatically start Shimbar and load your proxy configs when logging into macOS.")
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
                
                // --- SECTION 2: Daemon Connection Settings ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("Daemon Connection Settings")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Port Setting
                        HStack(alignment: .center, spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Local Proxy Port")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("The port number codex-shim listens on (default is 8765).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            TextField("", text: $portString, prompt: Text("8765"))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onSubmit {
                                    savePort()
                                }
                        }
                        
                        Divider()
                        
                        // Polling Interval
                        HStack(alignment: .center, spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Status Polling Interval")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("How often Shimbar checks the status of the local proxy daemon.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Slider(value: $pollingSeconds, in: 2...30, step: 1) {
                                    EmptyView()
                                }
                                .frame(width: 120)
                                .onChange(of: pollingSeconds) { _, newValue in
                                    AppSettings.shared.pollingInterval = newValue
                                    manager.stopPolling()
                                    manager.startPolling()
                                }
                                
                                Text("\(Int(pollingSeconds))s")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }
                
                // --- SECTION 3: CLI Integration ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("CLI Integration")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("codex-shim CLI Path")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text("Name or absolute path of the codex-shim executable.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                TextField("", text: $shimPathString, prompt: Text("codex-shim"))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 250)
                                    .onSubmit {
                                        AppSettings.shared.shimPath = shimPathString
                                        Task {
                                            await manager.bootstrap()
                                        }
                                    }
                            }
                            
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(manager.shimFound ? Color.green : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text(manager.shimFound
                                     ? manager.shimPath
                                     : "Not found — tap Re-detect")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                Button("Re-detect") {
                                    shimPathString = AppSettings.shared.shimPath
                                    Task {
                                        await manager.rediscoverShimPath()
                                        shimPathString = AppSettings.shared.shimPath
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
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
            loadSettings()
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func loadSettings() {
        launchAtLogin = LoginItemManager.isEnabled
        portString = String(AppSettings.shared.port)
        shimPathString = AppSettings.shared.shimPath
        pollingSeconds = AppSettings.shared.pollingInterval
    }
    
    private func savePort() {
        if let val = Int(portString), val > 0 && val < 65536 {
            AppSettings.shared.port = val
            Task {
                try? await manager.restart()
            }
        } else {
            portString = String(AppSettings.shared.port)
        }
    }
}

