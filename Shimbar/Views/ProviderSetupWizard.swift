// MARK: - ProviderSetupWizard.swift
// Shimbar – Multi-step wizard sheet to add a provider
// macOS 14+

import SwiftUI

struct ProviderSetupWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShimManager.self) private var manager
    
    // Wizard Steps
    enum Step {
        case selectProvider
        case enterCredentials
        case selectModels
    }
    
    @State private var currentStep: Step = .selectProvider
    
    // Step 1: Selected Provider
    @State private var selectedProvider: ProviderDefinition? = nil
    
    // Step 2: Credentials
    @State private var apiKey: String = ""
    @State private var customProviderName: String = ""
    @State private var customBaseURL: String = ""
    @State private var customProviderType: String = "openai"
    @State private var isValidating: Bool = false
    @State private var validationResult: ValidationResult? = nil
    @State private var discoveredModelIds: [String] = []
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert: Bool = false
    
    // Step 3: Selected Models
    @State private var checkedModelIds: Set<String> = []
    @State private var newCustomModelId: String = ""
    @State private var customModels: [ProviderModelDef] = []
    
    // Columns for provider selection grid
    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(wizardTitle)
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            Divider()
            
            // Content
            VStack {
                switch currentStep {
                case .selectProvider:
                    selectProviderStep
                case .enterCredentials:
                    enterCredentialsStep
                case .selectModels:
                    selectModelsStep
                }
            }
            .frame(maxHeight: .infinity)
            .padding(20)
            
            Divider()
            
            // Footer Navigation
            HStack {
                if currentStep != .selectProvider {
                    Button("Back") {
                        goBack()
                    }
                }
                
                Spacer()
                
                if currentStep == .selectProvider {
                    Button("Next") {
                        currentStep = .enterCredentials
                    }
                    .disabled(selectedProvider == nil)
                    .buttonStyle(.borderedProminent)
                } else if currentStep == .enterCredentials {
                    HStack(spacing: 8) {
                        if validationResult != nil {
                            Button("Skip Validation") {
                                skipValidationAndContinue()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Button(selectedProvider?.id == "custom" ? "Next" : "Validate & Next") {
                            if selectedProvider?.id == "custom" {
                                prepareCustomModels()
                                currentStep = .selectModels
                            } else {
                                validateAndNext()
                            }
                        }
                        .disabled(isNextDisabled)
                        .buttonStyle(.borderedProminent)
                    }
                } else if currentStep == .selectModels {
                    Button("Done") {
                        finishSetup()
                    }
                    .disabled(checkedModelIds.isEmpty && customModels.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 580, maxWidth: 800, minHeight: 500, maxHeight: 700)
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = errorMessage {
                Text(msg)
            }
        }
    }
    
    private var wizardTitle: String {
        switch currentStep {
        case .selectProvider:
            return "Step 1: Pick a Provider"
        case .enterCredentials:
            return "Step 2: Enter API Credentials"
        case .selectModels:
            return "Step 3: Select Models"
        }
    }
    
    // MARK: - Step 1: Select Provider
    
    private var selectProviderStep: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ProviderCatalog.providers) { provider in
                    ProviderCard(
                        provider: provider,
                        isSelected: selectedProvider?.id == provider.id,
                        action: {
                            selectedProvider = provider
                            // Auto fill placeholders/defaults
                            if provider.id != "custom" {
                                let stored = KeychainManager.getKey(forProvider: provider.id) ?? ""
                                if stored.isEmpty && provider.id == "omlx" {
                                    apiKey = "local"
                                } else {
                                    apiKey = stored
                                }
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Step 2: Enter Credentials
    
    private var enterCredentialsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let provider = selectedProvider {
                HStack(spacing: 12) {
                    Image(systemName: provider.icon)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(provider.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(provider.defaultBaseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)
                
                if provider.id == "custom" {
                    customProviderFields
                } else {
                    standardProviderFields(provider)
                }
                
                Spacer()
                
                // Secure note
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                    Text("API keys are saved securely in your macOS Keychain. They are never transmitted or saved anywhere else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
            }
        }
    }
    
    @ViewBuilder
    private func standardProviderFields(_ provider: ProviderDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("API Key")
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Link("Get an API Key", destination: provider.docsURL)
                    .font(.caption)
            }
            
            SecureField(provider.keyPlaceholder, text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            
            if isValidating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to validation endpoint...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } else if let result = validationResult {
                validationFeedbackView(result)
            }
        }
    }
    
    private var customProviderFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Provider Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("My Custom Endpoint", text: $customProviderName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://api.myllm.com/v1", text: $customBaseURL)
                    .textFieldStyle(.roundedBorder)
                if !customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidURL(customBaseURL) {
                    Text("Please enter a valid HTTP/HTTPS URL (starting with http:// or https://)")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider Protocol")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $customProviderType) {
                        Text("OpenAI-Compatible").tag("openai")
                        Text("Anthropic-Compatible").tag("anthropic")
                        Text("Generic").tag("generic-chat-completion-api")
                    }
                    .labelsHidden()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Optional credentials...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
    
    @ViewBuilder
    private func validationFeedbackView(_ result: ValidationResult) -> some View {
        switch result {
        case .valid(let models):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Key validated successfully! Found \(models.count) models.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .padding(.top, 4)
        case .invalid(let reason):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Invalid key: \(reason)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .padding(.top, 4)
        case .networkError(let err):
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
                Text("Network error: \(err)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(.top, 4)
        }
    }
    
    private var isNextDisabled: Bool {
        if let provider = selectedProvider {
            if provider.id == "custom" {
                return customProviderName.isEmpty || customBaseURL.isEmpty || !isValidURL(customBaseURL)
            } else if provider.id == "omlx" {
                return isValidating
            } else {
                return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating
            }
        }
        return true
    }
    
    // MARK: - Step 3: Select Models
    
    private var selectModelsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which models would you like to enable?")
                .font(.body)
                .foregroundStyle(.secondary)
            
            if selectedProvider?.id == "custom" {
                customModelsSelectionView
            } else {
                standardModelsSelectionView
            }
        }
    }
    
    private var standardModelsSelectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Models list
            ScrollView {
                VStack(spacing: 0) {
                    if let provider = selectedProvider {
                        let availableModels = (provider.id == "omlx" && !discoveredModelIds.isEmpty) ? discoveredCatalogModels : (provider.models.isEmpty ? discoveredCatalogModels : provider.models)
                        if availableModels.isEmpty {
                            Text("No models discovered. Complete setup to add models manually.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            ForEach(availableModels) { model in
                                Toggle(isOn: Binding(
                                    get: { checkedModelIds.contains(model.modelId) },
                                    set: { selected in
                                        if selected {
                                            checkedModelIds.insert(model.modelId)
                                        } else {
                                            checkedModelIds.remove(model.modelId)
                                        }
                                    }
                                )) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.displayName)
                                                .font(.body)
                                            Text(model.modelId)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if model.isRecommended {
                                            Text("Recommended")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(Color.accentColor)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().stroke(Color.accentColor, lineWidth: 1))
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .toggleStyle(.checkbox)
                                Divider().padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var customModelsSelectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Add custom model form
            HStack(spacing: 8) {
                TextField("Model ID (e.g. qwen:7b)", text: $newCustomModelId)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    addCustomModel()
                }
                .disabled(newCustomModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            // List of added models
            ScrollView {
                VStack(spacing: 0) {
                    if customModels.isEmpty {
                        Text("No custom models added yet. Add at least one above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(customModels) { model in
                            HStack {
                                Image(systemName: "cpu")
                                    .foregroundStyle(.secondary)
                                Text(model.displayName)
                                Spacer()
                                Button(role: .destructive) {
                                    customModels.removeAll { $0.modelId == model.modelId }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
            }
        }
    }
    
    private var discoveredCatalogModels: [ProviderModelDef] {
        discoveredModelIds.map { id in
            ProviderModelDef(
                modelId: id,
                displayName: id,
                maxContextLimit: nil,
                maxOutputTokens: nil,
                supportsImages: true,
                isRecommended: false
            )
        }
    }
    
    // MARK: - Navigation Functions
    
    private func goBack() {
        switch currentStep {
        case .selectProvider:
            break
        case .enterCredentials:
            currentStep = .selectProvider
        case .selectModels:
            currentStep = .enterCredentials
        }
    }
    
    private func validateAndNext() {
        guard let provider = selectedProvider else { return }
        
        isValidating = true
        validationResult = nil
        
        Task {
            let res = await ApiKeyValidator.validate(key: apiKey, provider: provider)
            
            await MainActor.run {
                self.isValidating = false
                self.validationResult = res
                
                switch res {
                case .valid(let models):
                    self.discoveredModelIds = models
                    // Select recommended models by default, or all if none recommended
                    if provider.models.isEmpty {
                        self.checkedModelIds = Set(models)
                    } else {
                        self.checkedModelIds = Set(provider.models.filter { $0.isRecommended }.map { $0.modelId })
                        if self.checkedModelIds.isEmpty {
                            self.checkedModelIds = Set(provider.models.map { $0.modelId })
                        }
                    }
                    self.currentStep = .selectModels
                case .invalid, .networkError:
                    // If validation fails, we STILL allow going next, but warn them, OR keep them here.
                    // For safety, let's keep them here so they correct their key. But we'll add an option to skip validation.
                    // Let's just let them click Next again to bypass validation if they are absolutely sure.
                    break
                }
            }
        }
    }
    
    private func skipValidationAndContinue() {
        guard let provider = selectedProvider else { return }
        // Populate checkedModelIds with provider default models
        self.discoveredModelIds = provider.models.map { $0.modelId }
        self.checkedModelIds = Set(provider.models.filter { $0.isRecommended }.map { $0.modelId })
        if self.checkedModelIds.isEmpty {
            self.checkedModelIds = Set(provider.models.map { $0.modelId })
        }
        self.currentStep = .selectModels
    }
    
    private func prepareCustomModels() {
        customModels = []
        newCustomModelId = ""
    }
    
    private func addCustomModel() {
        let cleaned = newCustomModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        
        let newDef = ProviderModelDef(
            modelId: cleaned,
            displayName: cleaned,
            maxContextLimit: nil,
            maxOutputTokens: nil,
            supportsImages: true,
            isRecommended: false
        )
        
        if !customModels.contains(where: { $0.modelId == cleaned }) {
            customModels.append(newDef)
        }
        
        newCustomModelId = ""
    }
    
    private func finishSetup() {
        guard let provider = selectedProvider else { return }
        
        Task {
            do {
                if provider.id == "custom" {
                    // Assemble a custom ProviderDefinition
                    let customDef = ProviderDefinition(
                        id: customProviderName.lowercased().replacingOccurrences(of: " ", with: "-"),
                        name: customProviderName,
                        icon: "wrench.and.screwdriver",
                        shimProvider: customProviderType,
                        defaultBaseURL: customBaseURL,
                        keyPlaceholder: "API key...",
                        keyValidationPath: "/models",
                        docsURL: URL(string: "https://github.com/0xSero/codex-shim")!,
                        models: customModels,
                        authStyle: .bearer
                    )
                    
                    try await manager.addProvider(provider: customDef, selectedModels: customModels, apiKey: apiKey)
                } else {
                    let availableModels: [ProviderModelDef]
                    if provider.id == "omlx" && !discoveredModelIds.isEmpty {
                        availableModels = discoveredCatalogModels
                    } else {
                        availableModels = provider.models.isEmpty ? discoveredCatalogModels : provider.models
                    }
                    let selectedModels = availableModels.filter { checkedModelIds.contains($0.modelId) }
                    
                    try await manager.addProvider(provider: provider, selectedModels: selectedModels, apiKey: apiKey)
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return url.scheme == "http" || url.scheme == "https"
    }
}

// MARK: - ProviderCard

struct ProviderCard: View {
    let provider: ProviderDefinition
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: provider.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                
                Text(provider.name)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 105, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.secondary.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovered = hover
        }
    }
}
