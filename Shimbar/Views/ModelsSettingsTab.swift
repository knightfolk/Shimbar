// MARK: - ModelsSettingsTab.swift
// Shimbar – Detailed models manager table
// macOS 14+

import SwiftUI

struct ModelsSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    @State private var selectedModelSlug: String? = nil
    @State private var showingEditorSheet = false
    @State private var editingModel: ShimModel? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Action bar
            HStack {
                Text("Configured Proxy Models")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        editingModel = nil
                        showingEditorSheet = true
                    } label: {
                        Label("Add Model", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        if let selectedSlug = selectedModelSlug,
                           let model = manager.models.first(where: { $0.slug == selectedSlug }) {
                            editingModel = model
                            showingEditorSheet = true
                        }
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedModelSlug == nil)
                    
                    Button(role: .destructive) {
                        deleteSelectedModel()
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedModelSlug == nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            Divider()
            
            // Models table
            if manager.models.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No Models Defined")
                        .font(.headline)
                    Text("Models are created automatically when you add providers. You can also add custom models manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedModelSlug) {
                    ForEach(manager.models) { model in
                        ModelRowView(model: model, isActive: manager.activeModel == model.slug)
                            .tag(model.slug)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .sheet(isPresented: $showingEditorSheet) {
            ModelEditorSheet(modelToEdit: editingModel)
                .environment(manager)
        }
    }
    
    private func deleteSelectedModel() {
        guard let selectedSlug = selectedModelSlug else { return }
        
        Task {
            do {
                let mManager = ModelsJsonManager.shared
                try mManager.load()
                mManager.models.removeAll { $0.slug == selectedSlug }
                try mManager.save()
                
                // Re-sync
                try await manager.generate()
                if manager.status.isRunning {
                    try? await manager.restart()
                } else {
                    await manager.refreshStatus()
                }
                
                await MainActor.run {
                    self.selectedModelSlug = nil
                }
            } catch {
                // Failed to delete model
            }
        }
    }
}

// MARK: - ModelRowView

struct ModelRowView: View {
    let model: ShimModel
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Active checkmark indicator
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 18)
            
            // Provider Icon
            Image(systemName: providerIcon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .fontWeight(.medium)
                    
                    if model.isPassthrough {
                        Text("Passthrough")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                    }
                }
                
                Text(model.slug)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(model.model)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            
            Text(contextText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
    
    private var providerIcon: String {
        if let providerDef = ProviderCatalog.provider(forBaseURL: model.baseUrl) {
            return providerDef.icon
        }
        return "cpu"
    }
    
    private var contextText: String {
        if let limit = model.maxContextLimit {
            if limit >= 1_000_000 {
                return "\(limit / 1_000_000)M ctx"
            } else if limit >= 1_000 {
                return "\(limit / 1_000)k ctx"
            }
            return "\(limit) ctx"
        }
        return "—"
    }
}
