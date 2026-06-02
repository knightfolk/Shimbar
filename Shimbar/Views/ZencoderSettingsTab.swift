import SwiftUI

struct ZencoderSettingsTab: View {
    @Environment(ShimManager.self) private var manager
    private let zencoderManager = ZencoderSettingsManager.shared
    private let workflowManager = ZenflowWorkflowManager.shared
    
    @State private var selectedSegment = 0
    
    @State private var selectedProjectPath: String?
    @State private var workflows: [ZenflowWorkflow] = []
    @State private var editingWorkflow: ZenflowWorkflow?
    @State private var isCreatingWorkflow = false
    @State private var showProjectPicker = false
    @State private var workflowToDelete: ZenflowWorkflow?
    @State private var showSyncAllConfirmation = false
    @State private var lastErrorMessage: String?
    @State private var showingErrorAlert = false
    @State private var workflowSearchText = ""
    
    private var filteredWorkflows: [ZenflowWorkflow] {
        guard !workflowSearchText.isEmpty else { return workflows }
        return workflows.filter {
            $0.title.localizedCaseInsensitiveContains(workflowSearchText) ||
            $0.fileName.localizedCaseInsensitiveContains(workflowSearchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSegment) {
                Text("Custom Models").tag(0)
                Text("Zenflow Workflows").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if selectedSegment == 0 {
                modelsSection
            } else {
                workflowsSection
            }
        }
        .sheet(item: $editingWorkflow) { workflow in
            ZenflowWorkflowEditorSheet(
                workflow: workflow,
                existingFileNames: workflows.map { $0.fileName },
                onSave: { savedWorkflow in
                    do {
                        try workflowManager.saveWorkflow(savedWorkflow)
                        refreshWorkflows()
                    } catch {
                        lastErrorMessage = error.localizedDescription
                        showingErrorAlert = true
                    }
                }
            )
        }
        .sheet(isPresented: $isCreatingWorkflow) {
            if let path = selectedProjectPath {
                ZenflowWorkflowEditorSheet(
                    workflow: ZenflowWorkflow(
                        fileName: "new-workflow.md",
                        title: "New Workflow",
                        content: "# New Workflow\n\n## Configuration\n- **Artifacts Path**: {@artifacts_path}\n\n---\n\n## Workflow Steps\n\n### [ ] Step 1: \n<!-- agent: developer -->\n",
                        projectPath: path
                    ),
                    existingFileNames: workflows.map { $0.fileName },
                    onSave: { savedWorkflow in
                        do {
                            try workflowManager.saveWorkflow(savedWorkflow)
                            refreshWorkflows()
                        } catch {
                            lastErrorMessage = error.localizedDescription
                            showingErrorAlert = true
                        }
                    }
                )
            }
        }
        .confirmationDialog(
            "Delete \"\(workflowToDelete?.title ?? "Workflow")\"?",
            isPresented: Binding(
                get: { workflowToDelete != nil },
                set: { if !$0 { workflowToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let workflow = workflowToDelete {
                    do {
                        try workflowManager.deleteWorkflow(workflow)
                        refreshWorkflows()
                    } catch {
                        lastErrorMessage = error.localizedDescription
                        showingErrorAlert = true
                    }
                }
                workflowToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                workflowToDelete = nil
            }
        } message: {
            Text("This will permanently remove the workflow file from disk. This action cannot be undone.")
        }
        .alert("Sync All to Zencoder?", isPresented: $showSyncAllConfirmation) {
            Button("Sync All", role: .destructive) {
                zencoderManager.syncFromShimbar(forceAll: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite your Zencoder settings.json with all current provider configurations.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = lastErrorMessage {
                Text(msg)
            }
        }
        .onAppear {
            if selectedProjectPath == nil {
                selectedProjectPath = workflowManager.recentProjects.first
            }
            if selectedProjectPath != nil {
                refreshWorkflows()
            }
        }
    }
    
    // MARK: - Models Section
    
    private var modelsSection: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Push your Shimbar providers into Zencoder's settings.json for use with custom models.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("API keys are written in plaintext to settings.json. Ensure your disk is encrypted (FileVault) and restrict file access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
                
                if let error = zencoderManager.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
                }
            }
            .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 16) {
                    let groups = manager.modelsManager.providerGroups()
                    
                    if groups.isEmpty {
                        ContentUnavailableView("No Providers", systemImage: "square.grid.2x2", description: Text("Add providers in the Providers tab first."))
                    } else {
                        ForEach(groups, id: \.baseUrl) { group in
                            if let providerDef = group.providerDef {
                                providerExportCard(providerDef: providerDef, group: group)
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Toggle("Auto-Sync on Changes", isOn: Binding(
                    get: { zencoderManager.isEnabled },
                    set: { zencoderManager.isEnabled = $0 }
                ))
                
                Spacer()
                
                Button("Sync All to Zencoder") {
                    showSyncAllConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Open settings.json") {
                    zencoderManager.openSettingsInFinder()
                }
            }
            .padding()
        }
    }
    
    private func providerExportCard(providerDef: ProviderDefinition, group: (providerDef: ProviderDefinition?, baseUrl: String, models: [ShimModel])) -> some View {
        let isExported = zencoderManager.exportedProviderIds.contains(providerDef.id)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: providerDef.icon)
                    .font(.title2)
                    .frame(width: 32)
                
                Text(providerDef.name)
                    .font(.headline)
                
                Spacer()
                
                if isExported {
                    Label("Exported", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                }
                
                Toggle("", isOn: Binding(
                    get: { isExported },
                    set: { newValue in
                        if newValue {
                            let apiKey = KeychainManager.getKey(forProvider: providerDef.id) ?? group.models.first?.apiKey ?? ""
                            zencoderManager.exportProvider(providerDef.id, baseUrl: group.baseUrl, apiKey: apiKey, models: group.models)
                        } else {
                            zencoderManager.removeProvider(providerDef.id)
                        }
                    }
                ))
                .labelsHidden()
            }
            
            Divider()
            
            if group.models.isEmpty {
                Text("No models configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(group.models) { model in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.square.fill")
                                .foregroundStyle(isExported ? .blue : .secondary)
                            Text(model.slug)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Workflows Section
    
    private var workflowsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Project:")
                    .fontWeight(.medium)
                
                if let path = selectedProjectPath {
                    Text((path as NSString).lastPathComponent)
                        .help(path)
                } else {
                    Text("None Selected")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Menu("Change\u{2026}") {
                    Button("Browse\u{2026}") { showProjectPicker = true }
                    
                    if !workflowManager.recentProjects.isEmpty {
                        Divider()
                        Text("Recent Projects")
                        ForEach(workflowManager.recentProjects, id: \.self) { path in
                            Button((path as NSString).lastPathComponent) {
                                selectedProjectPath = path
                                refreshWorkflows()
                            }
                            .help(path)
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            if !workflows.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter workflows\u{2026}", text: $workflowSearchText)
                        .textFieldStyle(.roundedBorder)
                    if !workflowSearchText.isEmpty {
                        Button {
                            workflowSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            if selectedProjectPath == nil {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Select a project directory to manage its Zenflow workflows.")
                )
                Button("Select Project Directory") {
                    showProjectPicker = true
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            } else {
                List {
                    if workflows.isEmpty {
                        Text("No workflows found in .zenflow/workflows/")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else if filteredWorkflows.isEmpty {
                        Text("No workflows match \"\(workflowSearchText)\"")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(filteredWorkflows) { workflow in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workflow.title)
                                        .font(.headline)
                                    HStack(spacing: 8) {
                                        Text(workflow.fileName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let date = workflow.lastModified {
                                            Text(date, style: .relative)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Edit") {
                                    editingWorkflow = workflow
                                }
                                .disabled(workflowToDelete != nil)
                                
                                Button("Delete") {
                                    workflowToDelete = workflow
                                }
                                .tint(.red)
                                .disabled(workflowToDelete != nil)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                
                HStack {
                    Button(action: { isCreatingWorkflow = true }) {
                        Label("New Workflow", systemImage: "plus")
                    }
                    
                    Menu {
                        ForEach(WorkflowTemplate.templates) { template in
                            Button(template.title) {
                                createFromTemplate(template)
                            }
                        }
                    } label: {
                        Label("From Template", systemImage: "doc.on.doc")
                    }
                    
                    Spacer()
                    
                    Text((selectedProjectPath ?? "").appending("/.zenflow/workflows/"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .fileImporter(
            isPresented: $showProjectPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedProjectPath = url.path
                    workflowManager.addRecentProject(url.path)
                    refreshWorkflows()
                }
            case .failure(let error):
                lastErrorMessage = "Failed to select directory: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }
    
    private func refreshWorkflows() {
        guard let path = selectedProjectPath else { return }
        workflows = workflowManager.loadWorkflows(from: path)
    }
    
    private func createFromTemplate(_ template: WorkflowTemplate) {
        guard let path = selectedProjectPath else { return }
        let workflow = ZenflowWorkflow(
            fileName: template.defaultFileName,
            title: template.title,
            content: template.content,
            projectPath: path
        )
        do {
            try workflowManager.saveWorkflow(workflow)
            refreshWorkflows()
        } catch {
            lastErrorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return .zero }
        
        let containerWidth = proposal.width ?? .infinity
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        
        for size in sizes {
            if currentRowWidth > 0, currentRowWidth + spacing + size.width > containerWidth {
                totalWidth = max(totalWidth, currentRowWidth)
                totalHeight += currentRowHeight + spacing
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth += currentRowWidth > 0 ? spacing + size.width : size.width
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }
        
        totalWidth = max(totalWidth, currentRowWidth)
        totalHeight += currentRowHeight
        
        return CGSize(width: totalWidth, height: totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += currentRowHeight + spacing
                currentRowHeight = 0
            }
            
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}
