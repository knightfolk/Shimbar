// MARK: - SettingsView.swift
// Shimbar – Main multi-tab preferences window container
// macOS 14+

import SwiftUI

struct SettingsView: View {
    @Environment(ShimManager.self) private var manager
    @Environment(ShimServer.self) private var server
    
    var body: some View {
        VStack(spacing: 0) {
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
                
                ZencoderSettingsTab()
                    .environment(manager)
                    .tabItem {
                        Label("Zencoder", systemImage: "wand.and.stars")
                    }
                
                AutoRouterSettingsTab()
                    .environment(manager)
                    .tabItem {
                        Label("Auto Router", systemImage: "arrow.triangle.branch")
                    }
                
                ZenflowRouterSettingsTab()
                    .environment(manager)
                    .tabItem {
                        Label("Zenflow Router", systemImage: "signpost.right.and.left")
                    }
                
                RouterStatsTab()
                    .tabItem {
                        Label("Router Stats", systemImage: "chart.bar")
                    }
                
                AdvancedSettingsTab()
                    .environment(manager)
                    .environment(server)
                    .tabItem {
                        Label("Advanced", systemImage: "gearshape.2")
                    }
            }
            
            HStack {
                Spacer()
                Text("Powered by")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button(action: {
                    if let url = URL(string: "https://github.com/0xSero/codex-shim") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("codex-shim")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.bottom, 4)
        }
        .frame(minWidth: 620, maxWidth: 850, minHeight: 480, maxHeight: 700)
    }
}
