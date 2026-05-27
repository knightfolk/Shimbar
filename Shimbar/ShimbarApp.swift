// MARK: - ShimbarApp.swift
// Shimbar – Application Entry Point
// macOS 14+

import SwiftUI

@main
struct ShimbarApp: App {
    // Initialize the main manager that orchestrates the daemon and models configurations
    @State private var shimManager = ShimManager.shared
    
    var body: some Scene {
        // Menu bar item showing the daemon status icon
        MenuBarExtra {
            ShimMenuView()
                .environment(shimManager)
        } label: {
            ShimStatusIcon(status: shimManager.status)
        }
        .menuBarExtraStyle(.window)
        
        // Multi-tab Preferences / Settings Window
        Settings {
            SettingsView()
                .environment(shimManager)
        }
    }
    
    init() {
        // Bootstrap the app by checking paths, settings, and initial statuses
        Task { @MainActor in
            await ShimManager.shared.bootstrap()
            ShimManager.shared.startPolling()
        }
    }
}
