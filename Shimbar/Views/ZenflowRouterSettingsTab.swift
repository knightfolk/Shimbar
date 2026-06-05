// Shimbar – Zenflow Router configuration UI
// macOS 14+

import SwiftUI

struct ZenflowRouterSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    @State private var viewModel = ZenflowRouterSettingsViewModel()
    @State private var projectSelection = ZenflowProjectSelection.shared
    @State private var showProjectPicker = false

    private var modelSlugs: [String] {
        manager.modelsManager.models.map(\.slug)
    }

    private var workflowFileNames: [String] {
        viewModel.workflowFileNames
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                projectSelector

                if projectSelection.selectedPath == nil {
                    ContentUnavailableView(
                        "No Project Selected",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Select a project directory to configure the Zenflow auto router.")
                    )
                } else {
                    routerConfigSection
                    actionBar
                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .fileImporter(
            isPresented: $showProjectPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.setSelectedProject(url.path)
                }
            case .failure(let error):
                viewModel.saveError = "Failed to select directory: \(error.localizedDescription)"
            }
        }
        .onAppear {
            viewModel.availableModelSlugs = modelSlugs
            viewModel.refresh()
        }
        .onChange(of: projectSelection.selectedPath) { _, _ in
            viewModel.refresh()
        }
        .onChange(of: modelSlugs) { _, newValue in
            viewModel.availableModelSlugs = newValue
        }
    }

    // MARK: - Subviews

    private var projectSelector: some View {
        HStack {
            Text("Project:")
                .fontWeight(.medium)

            if let path = projectSelection.selectedPath {
                Text((path as NSString).lastPathComponent)
                    .help(path)
            } else {
                Text("None Selected")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu("Change\u{2026}") {
                Button("Browse\u{2026}") { showProjectPicker = true }

                if !ZenflowWorkflowManager.shared.recentProjects.isEmpty {
                    Divider()
                    Text("Recent Projects")
                    ForEach(ZenflowWorkflowManager.shared.recentProjects, id: \.self) { path in
                        Button((path as NSString).lastPathComponent) {
                            viewModel.setSelectedProject(path)
                        }
                        .help(path)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var routerConfigSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zenflow Auto Router")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Configure per-task smart workflow routing. The classifier evaluates each prompt and picks the best workflow candidate.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { viewModel.enabled },
                    set: { viewModel.enabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Zenflow Auto Router")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Routes new Zenflow tasks to the best workflow candidate based on task content.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if viewModel.enabled {
                    Divider()

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Classifier Model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Classifier", selection: Binding(
                                get: { viewModel.classifier },
                                set: { viewModel.classifier = $0 }
                            )) {
                                Text("Select\u{2026}").tag("")
                                ForEach(modelSlugs, id: \.self) { slug in
                                    Text(slug).tag(slug)
                                }
                            }
                            .frame(minWidth: 200)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default Fallback Workflow")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Default", selection: Binding(
                                get: { viewModel.defaultWorkflow },
                                set: { viewModel.defaultWorkflow = $0 }
                            )) {
                                Text("Select\u{2026}").tag("")
                                ForEach(workflowFileNames, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .frame(minWidth: 200)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Threshold: \(viewModel.threshold, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { viewModel.threshold },
                            set: { viewModel.threshold = $0 }
                        ), in: 0.0...1.0, step: 0.05)
                    }

                    Toggle(isOn: Binding(
                        get: { viewModel.cache },
                        set: { viewModel.cache = $0 }
                    )) {
                        Text("Cache routing decisions per task")
                            .font(.body)
                    }
                    .toggleStyle(.checkbox)

                    Divider()

                    candidatesSection
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Candidates")
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Button("+ Add Candidate") {
                    viewModel.addCandidate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.canAddCandidate)
            }

            if viewModel.candidates.isEmpty {
                Text("No candidates configured. Add at least two workflows to route between.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            ForEach($viewModel.candidates) { $candidate in
                candidateRow(candidate: $candidate)
            }
        }
    }

    private func candidateRow(candidate: Binding<ZenflowRouterCandidate>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Picker("Workflow", selection: candidate.workflowFileName) {
                    ForEach(workflowFileNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(minWidth: 180)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cost")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Cost", value: candidate.cost, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Quality")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Quality", value: candidate.quality, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }

                Spacer()

                Button(role: .destructive) {
                    viewModel.removeCandidate(candidate.wrappedValue)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            TextField("Capability card (shown to classifier)", text: candidate.card, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .font(.system(size: 11))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor).opacity(0.4)))
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            if let error = viewModel.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Refresh") {
                viewModel.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Reload workflows from disk and discard in-memory changes")

            Button("Discard") {
                viewModel.discard()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.isSaving)

            Button("Save") {
                viewModel.save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canSave)
        }
    }
}
