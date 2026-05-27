// MARK: - ModelEditorSheet.swift
// Shimbar – Edit or add a single model entry manually
// macOS 14+

import SwiftUI

struct ModelEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShimManager.self) private var manager
    
    // The model being edited, if nil, we are adding a new model manually
    let modelToEdit: ShimModel?
    
    // Form fields
    @State private var slug: String = ""
    @State private var displayName: String = ""
    @State private var modelId: String = ""
    @State private var provider: String = "openai"
    @State private var baseUrl: String = ""
    @State private var apiKey: String = ""
    @State private var maxContextLimit: String = ""
    @State private var maxOutputTokens: String = ""
    @State private var noImageSupport: Bool = false
    
    // Extra headers key-values
    @State private var extraHeaders: [(key: String, value: String)] = []
    @State private var newHeaderKey: String = ""
    @State private var newHeaderValue: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(modelToEdit == nil ? "Add Model Manually" : "Edit Model Settings")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            Divider()
            
            // Form body
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model Nickname / Slug")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("e.g. my-fast-gpt4", text: $slug)
                                .textFieldStyle(.roundedBorder)
                                .disabled(modelToEdit != nil) // Cannot change slug after creation (it's the unique key)
                            if modelToEdit == nil {
                                Text("This is the unique handle you will use in your API requests.")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Display Name")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("e.g. My Fast GPT-4", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Upstream Model ID")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("e.g. gpt-4o-2024-05-13", text: $modelId)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    Group {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Provider Protocol")
                                    .font(.caption).foregroundStyle(.secondary)
                                Picker("", selection: $provider) {
                                    Text("OpenAI-Compatible").tag("openai")
                                    Text("Anthropic-Compatible").tag("anthropic")
                                    Text("Generic").tag("generic-chat-completion-api")
                                }
                                .labelsHidden()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Base URL")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextField("https://api.openai.com/v1", text: $baseUrl)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key / Bearer Credentials")
                                .font(.caption).foregroundStyle(.secondary)
                            SecureField("Enter API Key (will be saved in Keychain)...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    Group {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Max Context Limit (Tokens)")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextField("Optional (e.g. 128000)", text: $maxContextLimit)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Max Output Limit (Tokens)")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextField("Optional (e.g. 4096)", text: $maxOutputTokens)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        Toggle("Disable Image / Vision Support", isOn: $noImageSupport)
                            .toggleStyle(.checkbox)
                    }
                    
                    // Extra Headers
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom HTTP Headers")
                            .font(.caption).foregroundStyle(.secondary)
                        
                        if !extraHeaders.isEmpty {
                            VStack(spacing: 4) {
                                ForEach(0..<extraHeaders.count, id: \.self) { index in
                                    HStack {
                                        Text(extraHeaders[index].key)
                                            .fontWeight(.medium)
                                        Text(":")
                                            .foregroundStyle(.secondary)
                                        Text(extraHeaders[index].value)
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            extraHeaders.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
                        }
                        
                        HStack(spacing: 6) {
                            TextField("Header Key", text: $newHeaderKey)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            TextField("Value", text: $newHeaderValue)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            Button("Add") {
                                addHeader()
                            }
                            .controlSize(.small)
                            .disabled(newHeaderKey.isEmpty || newHeaderValue.isEmpty)
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Save") {
                    saveModel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            populateFields()
        }
    }
    
    private var isSaveDisabled: Bool {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func addHeader() {
        let key = newHeaderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let val = newHeaderValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty && !val.isEmpty else { return }
        
        extraHeaders.append((key: key, value: val))
        newHeaderKey = ""
        newHeaderValue = ""
    }
    
    private func populateFields() {
        guard let model = modelToEdit else { return }
        
        slug = model.slug
        displayName = model.displayName
        modelId = model.model
        provider = model.provider
        baseUrl = model.baseUrl
        apiKey = model.apiKey
        
        if let maxCtx = model.maxContextLimit {
            maxContextLimit = String(maxCtx)
        }
        if let maxOut = model.maxOutputTokens {
            maxOutputTokens = String(maxOut)
        }
        
        noImageSupport = model.noImageSupport
        
        extraHeaders = model.extraHeaders.map { (key: $0.key, value: $0.value) }.sorted { $0.key < $1.key }
    }
    
    private func saveModel() {
        let headersDict = Dictionary(uniqueKeysWithValues: extraHeaders.map { ($0.key, $0.value) })
        
        let newModel = ShimModel(
            slug: slug.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelId.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: provider,
            baseUrl: baseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            maxContextLimit: Int(maxContextLimit),
            maxOutputTokens: Int(maxOutputTokens),
            noImageSupport: noImageSupport,
            extraHeaders: headersDict
        )
        
        Task {
            do {
                let manager = ModelsJsonManager.shared
                try manager.load()
                
                if let index = manager.models.firstIndex(where: { $0.slug == newModel.slug }) {
                    manager.models[index] = newModel
                } else {
                    manager.models.append(newModel)
                }
                
                try manager.save()
                
                // Regenerate CLI configs and trigger a quick reload/restart
                try await self.manager.generate()
                if self.manager.status.isRunning {
                    try await self.manager.restart()
                } else {
                    await self.manager.refreshStatus()
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                // Handle error
            }
        }
    }
}
