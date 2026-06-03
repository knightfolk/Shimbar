// MARK: - AutoRouterSettingsTab.swift
// Shimbar – Auto Router configuration UI
// macOS 14+

import SwiftUI

struct AutoRouterSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    @State private var enabled = false
    @State private var classifier: String = ""
    @State private var threshold: Double = 0.7
    @State private var defaultModel: String = ""
    @State private var cache = true
    @State private var slug: String = "codex-auto"
    @State private var displayName: String = "Auto (smart routing)"
    @State private var candidates: [RouterCandidate] = []
    @State private var isSaving = false
    @State private var showSaveError: String?

    private var modelSlugs: [String] {
        manager.modelsManager.models.map(\.slug)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Auto Router")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Configure per-task smart model routing. The classifier evaluates each prompt and picks the cheapest model that can handle it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $enabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Auto Router")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("Adds a \"codex-auto\" model that routes tasks to the best candidate.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)

                        if enabled {
                            Divider()

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Classifier Model")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Classifier", selection: $classifier) {
                                        Text("Select…").tag("")
                                        ForEach(modelSlugs, id: \.self) { slug in
                                            Text(slug).tag(slug)
                                        }
                                    }
                                    .frame(minWidth: 200)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Default Fallback")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Default", selection: $defaultModel) {
                                        Text("Select…").tag("")
                                        ForEach(modelSlugs, id: \.self) { slug in
                                            Text(slug).tag(slug)
                                        }
                                    }
                                    .frame(minWidth: 200)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Threshold: \(threshold, specifier: "%.2f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(value: $threshold, in: 0.0...1.0, step: 0.05)
                            }

                            Toggle(isOn: $cache) {
                                Text("Cache routing decisions per task")
                                    .font(.body)
                            }
                            .toggleStyle(.checkbox)

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Candidates")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Button("+ Add Candidate") {
                                        candidates.append(RouterCandidate(
                                            slug: modelSlugs.first ?? "",
                                            cost: 1.0,
                                            supportsImages: false,
                                            card: ""
                                        ))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(modelSlugs.isEmpty)
                                }

                                if candidates.isEmpty {
                                    Text("No candidates configured. Add at least two models to route between.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 4)
                                }

                                ForEach($candidates) { $candidate in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 12) {
                                            Picker("Model", selection: $candidate.slug) {
                                                ForEach(modelSlugs, id: \.self) { slug in
                                                    Text(slug).tag(slug)
                                                }
                                            }
                                            .frame(minWidth: 180)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Cost")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                TextField("Cost", value: $candidate.cost, format: .number)
                                                    .textFieldStyle(.roundedBorder)
                                                    .frame(width: 70)
                                            }

                                            Toggle("Images", isOn: $candidate.supportsImages)
                                                .toggleStyle(.checkbox)

                                            Spacer()

                                            Button(role: .destructive) {
                                                candidates.removeAll { $0.slug == candidate.slug }
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundStyle(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        TextField("Capability card (shown to classifier)", text: $candidate.card, axis: .vertical)
                                            .textFieldStyle(.roundedBorder)
                                            .lineLimit(2...4)
                                            .font(.system(size: 11))
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor).opacity(0.4)))
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }

                HStack {
                    Spacer()
                    if let error = showSaveError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("Save & Apply") {
                        saveRouterConfig()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            loadRouterConfig()
        }
    }

    private func loadRouterConfig() {
        let router = manager.modelsManager.routerConfig
        enabled = router?.enabled ?? false
        classifier = router?.classifier ?? modelSlugs.first ?? ""
        threshold = router?.threshold ?? 0.7
        defaultModel = router?.defaultModel ?? modelSlugs.first ?? ""
        cache = router?.cache ?? true
        slug = router?.slug ?? "codex-auto"
        displayName = router?.displayName ?? "Auto (smart routing)"
        candidates = router?.candidates ?? []
    }

    private func saveRouterConfig() {
        isSaving = true
        showSaveError = nil

        if enabled && candidates.count < 2 {
            showSaveError = "Add at least 2 candidates."
            isSaving = false
            return
        }

        if enabled && classifier.isEmpty {
            showSaveError = "Select a classifier model."
            isSaving = false
            return
        }

        if enabled && defaultModel.isEmpty {
            showSaveError = "Select a default fallback model."
            isSaving = false
            return
        }

        let config: RouterConfig?
        if enabled {
            config = RouterConfig(
                enabled: true,
                slug: slug,
                displayName: displayName,
                classifier: classifier,
                threshold: threshold,
                defaultModel: defaultModel,
                cache: cache,
                candidates: candidates
            )
        } else {
            if var existing = manager.modelsManager.routerConfig {
                existing.enabled = false
                config = existing
            } else {
                config = nil
            }
        }

        manager.modelsManager.routerConfig = config

        do {
            try manager.modelsManager.save()
            Task {
                try? await manager.generate()
                if manager.status.isRunning {
                    try? await manager.restart()
                }
                isSaving = false
            }
        } catch {
            showSaveError = error.localizedDescription
            isSaving = false
        }
    }
}
