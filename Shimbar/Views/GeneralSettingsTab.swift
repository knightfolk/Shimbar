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
    
    var body: some View {
        Form {
            Section {
                // Launch at Login
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            try LoginItemManager.setEnabled(newValue)
                            launchAtLogin = newValue
                        } catch {
                            // Failed to set login item status
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start Shimbar on System Launch")
                            .font(.body)
                        Text("Automatically start Shimbar and load your proxy configs when logging into macOS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            } header: {
                Text("System Options")
                    .font(.headline)
            }
            .padding(.bottom, 12)
            
            Section {
                // Port Setting
                LabeledContent {
                    TextField("8765", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit {
                            savePort()
                        }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Proxy Port")
                        Text("The port number codex-shim listens on. (Default is 8765)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider().padding(.vertical, 8)
                
                // Polling Interval
                LabeledContent {
                    HStack(spacing: 8) {
                        Slider(value: $pollingSeconds, in: 2...30, step: 1) {
                            EmptyView()
                        }
                        .frame(width: 140)
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
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status Polling Interval")
                        Text("How often Shimbar checks the status of the local proxy daemon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Daemon Connection Settings")
                    .font(.headline)
            }
            .padding(.bottom, 12)
            
            Section {
                // CLI Binary Path
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 6) {
                        TextField("codex-shim", text: $shimPathString)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                AppSettings.shared.shimPath = shimPathString
                                Task {
                                    await manager.bootstrap()
                                }
                            }
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(manager.shimFound ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(manager.shimFound
                                 ? manager.shimPath
                                 : "Not found — tap Re-detect")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Re-detect") {
                                shimPathString = AppSettings.shared.shimPath
                                Task {
                                    await manager.rediscoverShimPath()
                                    shimPathString = AppSettings.shared.shimPath
                                }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                    .frame(width: 250)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("codex-shim CLI Path")
                        Text("Name or absolute path of the codex-shim executable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("CLI Integration")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSettings()
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
