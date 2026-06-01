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
                
                // --- SECTION 4: codex-shim Updates ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("codex-shim Updates")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Version status row
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Version Status")
                                    .font(.body)
                                    .fontWeight(.medium)
                                
                                if manager.updater.updateAvailable {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 6, height: 6)
                                        Text("Update available")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                } else if manager.updater.localCommitHash != nil {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text("Up to date")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                } else {
                                    Text("Not checked yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                if let local = manager.updater.localCommitHash {
                                    HStack(spacing: 4) {
                                        Text("Local:")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Text(local)
                                            .font(.system(size: 10, design: .monospaced))
                                    }
                                }
                                if let remote = manager.updater.remoteCommitHash {
                                    HStack(spacing: 4) {
                                        Text("Remote:")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Text(remote)
                                            .font(.system(size: 10, design: .monospaced))
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Action buttons and last check time
                        HStack(spacing: 8) {
                            Button(action: {
                                Task {
                                    await manager.updater.checkForUpdate(shimPath: manager.shimPath)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    if manager.updater.isChecking {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11))
                                    }
                                    Text(manager.updater.isChecking ? "Checking…" : "Check for Updates")
                                        .font(.system(size: 12))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(manager.updater.isChecking || !manager.shimFound)
                            
                            if manager.updater.updateAvailable {
                                Button(action: {
                                    Task {
                                        await manager.updater.performUpdate(shimManager: manager)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        if manager.updater.isUpdating {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Image(systemName: "arrow.down.circle")
                                                .font(.system(size: 11))
                                        }
                                        Text(manager.updater.isUpdating ? "Updating…" : "Update Now")
                                            .font(.system(size: 12))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(manager.updater.isUpdating)
                            }
                            
                            Spacer()
                            
                            if let lastCheck = manager.updater.lastCheckDate {
                                Text("Checked \(lastCheck, style: .relative) ago")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        // Error display
                        if let err = manager.updater.lastUpdateError {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                Text(err)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        // Update log (expandable)
                        if !manager.updater.updateLog.isEmpty {
                            DisclosureGroup("Update Log") {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(0..<manager.updater.updateLog.count, id: \.self) { i in
                                            Text(manager.updater.updateLog[i])
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                }
                                .frame(maxHeight: 120)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor).opacity(0.8)))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                            }
                            .font(.caption)
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

