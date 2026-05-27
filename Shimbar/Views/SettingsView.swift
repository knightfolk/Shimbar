// MARK: - SettingsView.swift
// Shimbar – Main multi-tab preferences window container
// macOS 14+

import SwiftUI

struct SettingsView: View {
    @Environment(ShimManager.self) private var manager
    
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(manager)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            ProvidersSettingsTab()
                .environment(manager)
                .tabItem {
                    Label("Providers", systemImage: "square.grid.2x2")
                }
            
            ModelsSettingsTab()
                .environment(manager)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
            
            AdvancedSettingsTab()
                .environment(manager)
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .frame(minWidth: 620, maxWidth: 850, minHeight: 480, maxHeight: 700)
    }
}
