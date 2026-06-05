// MARK: - ShimbarApp.swift
// Shimbar – Application Entry Point
// macOS 14+

import SwiftUI

@main
struct ShimbarApp: App {
    // Initialize the main manager that orchestrates the daemon and models configurations
    @State private var shimManager = ShimManager.shared
    // Zenflow auto router config / cache / decision-log manager.
    @State private var routerManager = ZenflowRouterManager.shared
    // Native in-process server (Phase 9).
    @State private var shimServer = ShimServer.shared

    var body: some Scene {
        // Menu bar item showing the daemon status icon
        MenuBarExtra {
            ShimMenuView()
                .environment(shimManager)
                .environment(routerManager)
                .environment(shimServer)
        } label: {
            ShimStatusIcon(status: shimManager.status)
        }
        .menuBarExtraStyle(.window)

        // Multi-tab Preferences / Settings Window
        Settings {
            SettingsView()
                .environment(shimManager)
                .environment(routerManager)
                .environment(shimServer)
        }
    }
    
    init() {
        // Bootstrap the app by checking paths, settings, and initial statuses
        Task { @MainActor in
            await ShimManager.shared.bootstrap()
            ShimManager.shared.startPolling()
            
            // Check if onboarding/diagnostics is needed (binary missing or models empty)
            let hasBinary = ShimManager.shared.shimFound
            let hasModels = ModelsJsonManager.shared.hasModels
            
            if !hasBinary || !hasModels {
                OnboardingWindowManager.shared.show(manager: ShimManager.shared)
            }
        }
    }
}
