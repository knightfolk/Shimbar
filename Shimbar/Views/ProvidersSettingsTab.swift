// MARK: - ProvidersSettingsTab.swift
// Shimbar – Manage configured AI providers
// macOS 14+

import SwiftUI

struct ProvidersSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    @State private var showingAddWizard = false
    @State private var editingProvider: String? = nil // Stores providerId being edited
    @State private var newApiKey: String = ""
    @State private var showingEditAlert = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Providers")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Manage your configured LLM hosts, API endpoints, and access keys.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showingAddWizard = true
                    } label: {
                        Label("Add Provider", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                let groups = ModelsJsonManager.shared.providerGroups()
                
                if groups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("No Providers Configured")
                            .font(.headline)
                        Text("Get started by adding a provider (like OpenAI, Anthropic, or DeepSeek) using the setup wizard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button("Launch Setup Wizard") {
                            showingAddWizard = true
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .padding(.top, 10)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(groups, id: \.baseUrl) { group in
                            ProviderGroupCard(
                                providerDef: group.providerDef,
                                baseUrl: group.baseUrl,
                                models: group.models,
                                onEditKey: {
                                    if let prov = group.providerDef {
                                        editingProvider = prov.id
                                    } else {
                                        editingProvider = group.baseUrl
                                    }
                                    newApiKey = KeychainManager.getKey(forProvider: group.providerDef?.id ?? "") ?? ""
                                    showingEditAlert = true
                                },
                                onRemove: {
                                    removeProvider(group)
                                }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showingAddWizard) {
            ProviderSetupWizard()
                .environment(manager)
        }
        .sheet(isPresented: $showingEditAlert) {
            EditApiKeySheet(
                title: editingProviderTitle,
                apiKey: $newApiKey,
                onSave: {
                    saveNewKey()
                }
            )
        }
    }
    
    private var editingProviderTitle: String {
        guard let providerId = editingProvider else { return "Update Credentials" }
        if let provider = ProviderCatalog.provider(forId: providerId) {
            return "Update \(provider.name) API Key"
        }
        return "Update Custom Provider Credentials"
    }
    
    private func saveNewKey() {
        guard let identifier = editingProvider else { return }
        
        let managerObj = ModelsJsonManager.shared
        
        // Find matching base URL
        var matchBaseUrl = identifier
        if let provider = ProviderCatalog.provider(forId: identifier) {
            matchBaseUrl = provider.defaultBaseURL
        }
        
        do {
            try managerObj.updateApiKey(for: matchBaseUrl, newKey: newApiKey)
            
            // Re-sync
            Task {
                try? await manager.generate()
                if manager.status.isRunning {
                    try? await manager.restart()
                } else {
                    await manager.refreshStatus()
                }
            }
        } catch {
            // Handle error
        }
        
        showingEditAlert = false
        editingProvider = nil
        newApiKey = ""
    }
    
    private func removeProvider(_ group: (providerDef: ProviderDefinition?, baseUrl: String, models: [ShimModel])) {
        let identifier = group.providerDef?.id ?? group.baseUrl
        
        Task {
            do {
                try await manager.removeProvider(identifier)
            } catch {
                // Failed to remove provider
            }
        }
    }
}

// MARK: - ProviderGroupCard

struct ProviderGroupCard: View {
    let providerDef: ProviderDefinition?
    let baseUrl: String
    let models: [ShimModel]
    
    let onEditKey: () -> Void
    let onRemove: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                // Icon / Avatar
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: providerDef?.icon ?? "server.rack")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(providerDef?.name ?? customNameFromUrl)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(baseUrl)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Status Indicator
                Circle()
                    .fill(Color.green) // If loaded, it's active
                    .frame(width: 7, height: 7)
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Models Configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(models.count) models")
                        .font(.body)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Edit Key", action: onEditKey)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hover in
            isHovered = hover
        }
    }
    
    private var customNameFromUrl: String {
        if let host = URL(string: baseUrl)?.host {
            return host.capitalized
        }
        return "Custom Provider"
    }
}

// MARK: - EditApiKeySheet

struct EditApiKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var apiKey: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key / Bearer Credentials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                SecureField("Enter new credentials here...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                
                Text("Saving this updates all models linked to this provider configuration.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Save Key") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimimmingCharacters().isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 420, height: 200)
    }
}

extension String {
    func trimimmingCharacters() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
