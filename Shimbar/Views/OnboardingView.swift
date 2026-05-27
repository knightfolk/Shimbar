// MARK: - OnboardingView.swift
// Shimbar – User onboarding and dependency checklist screen
// macOS 14+

import SwiftUI

struct OnboardingView: View {
    @State private var validator = StartupValidator()
    @Environment(ShimManager.self) private var manager
    
    @State private var showingProviderSetup = false
    @State private var isAutoSetupRunning = false
    @State private var autoSetupMessage: String? = nil
    
    // Callback to notify the app that onboarding was successfully completed
    var onCompletion: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with gorgeous premium gradient & logo
            headerSection
            
            Divider()
            
            // Live Checklist
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(validator.items) { item in
                        CheckRow(item: item, onFix: {
                            handleFix(for: item)
                        })
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 24)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            
            Divider()
            
            // Footer section with diagnostic action and main continue buttons
            footerSection
        }
        .frame(minWidth: 580, maxWidth: 800, minHeight: 500, maxHeight: 700)
        .onAppear {
            runDiagnostics()
        }
        .sheet(isPresented: $showingProviderSetup, onDismiss: {
            runDiagnostics()
        }) {
            ProviderSetupWizard()
                .environment(manager)
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Shiny gem icon referencing "shim"
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.indigo, Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.indigo.opacity(0.3), radius: 6, x: 0, y: 3)
                
                Image(systemName: "diamond.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Shimbar Onboarding")
                    .font(.system(size: 18, weight: .bold))
                Text("Let's configure and validate your environment before running the shim.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.all, 20)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        HStack {
            Button(action: runDiagnostics) {
                HStack(spacing: 6) {
                    if validator.isChecking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Re-run Diagnostics")
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .disabled(validator.isChecking)
            
            Spacer()
            
            Button(action: {
                onCompletion()
            }) {
                Text(validator.hasCriticalFailures ? "Resolve Critical Issues" : "Start Using Shimbar")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 160, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .tint(validator.isFullyReady ? Color.indigo : Color.secondary)
            .disabled(!validator.isFullyReady)
        }
        .padding(.all, 16)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Diagnostics & Fixes
    
    private func runDiagnostics() {
        Task {
            await validator.performAllChecks()
        }
    }
    
    private func handleFix(for item: StartupValidator.CheckItem) {
        switch item.id {
        case "binary":
            runAutoSetup()
        case "models":
            showingProviderSetup = true
        case "codexApp":
            if let url = URL(string: "https://github.com/imranbarbhuiya/codex-desktop/releases") {
                NSWorkspace.shared.open(url)
            }
        case "npx":
            if let url = URL(string: "https://nodejs.org") {
                NSWorkspace.shared.open(url)
            }
        case "writePerm":
            openSystemSettingsFDA()
        default:
            break
        }
    }
    
    private func runAutoSetup() {
        isAutoSetupRunning = true
        Task {
            await manager.rediscoverShimPath()
            await validator.performAllChecks()
            isAutoSetupRunning = false
        }
    }
    
    private func openSystemSettingsFDA() {
        let alert = NSAlert()
        alert.messageText = "How to Grant Full Disk Access"
        alert.informativeText = "macOS requires you to manually add Shimbar to the Full Disk Access list:\n\n1. Click 'Open Settings' to open the Full Disk Access panel.\n2. Click the '+' (plus) button at the bottom of the list of apps.\n3. Enter your Mac password/use Touch ID if prompted.\n4. Navigate to your Applications folder (or wherever Shimbar.app is located) and select Shimbar.app.\n5. Ensure the toggle switch next to Shimbar in the list is ON (green)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - CheckRow View

struct CheckRow: View {
    let item: StartupValidator.CheckItem
    var onFix: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Status Icon with matching colors
            statusIcon
                .frame(width: 24, height: 24)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                    
                    if !item.isCritical {
                        Text("Optional")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(item.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Show status detail message on failure or warning
                if case .failure(let msg) = item.status {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.top, 1)
                } else if case .warning(let msg) = item.status {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.top, 1)
                }
            }
            
            Spacer()
            
            // Action button based on status
            fixButton
        }
        .padding(.all, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.alternatingContentBackgroundColors[0]).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .checking:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 17))
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 18))
        }
    }
    
    private var borderColor: Color {
        switch item.status {
        case .failure:
            return Color.red.opacity(0.15)
        case .warning:
            return Color.orange.opacity(0.15)
        default:
            return Color.clear
        }
    }
    
    @ViewBuilder
    private var fixButton: some View {
        switch item.status {
        case .checking, .success:
            EmptyView()
        case .warning, .failure:
            Button(action: onFix) {
                Text(fixButtonTitle)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(item.isCritical ? Color.indigo : Color.secondary)
        }
    }
    
    private var fixButtonTitle: String {
        switch item.id {
        case "binary": return "Auto-Detect"
        case "models": return "Configure"
        case "codexApp": return "Download"
        case "npx": return "Install"
        case "writePerm": return "Grant FDA"
        default: return "Fix"
        }
    }
}
