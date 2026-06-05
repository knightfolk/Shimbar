// Shimbar – Zenflow Router settings view-model
// macOS 14+

import Foundation
import Observation

@MainActor
@Observable
final class ZenflowRouterSettingsViewModel {

    // MARK: - Editable state

    var enabled: Bool = false
    var classifier: String = ""
    var threshold: Double = 0.75
    var defaultWorkflow: String = ""
    var cache: Bool = true
    var candidates: [ZenflowRouterCandidate] = []

    // MARK: - Loaded data

    var workflows: [ZenflowWorkflow] = []

    // MARK: - Save state

    var isSaving: Bool = false
    var saveError: String?

    // MARK: - Inputs (set by the view)

    /// Slugs of models currently available from `ShimManager.modelsManager.models`.
    /// The view refreshes this whenever the manager's models change.
    var availableModelSlugs: [String] = []

    // MARK: - Dependencies

    private let routerManager: ZenflowRouterManager
    private let workflowManager: ZenflowWorkflowManager
    private let projectSelection: ZenflowProjectSelection

    init(
        routerManager: ZenflowRouterManager = .shared,
        workflowManager: ZenflowWorkflowManager = .shared,
        projectSelection: ZenflowProjectSelection = .shared
    ) {
        self.routerManager = routerManager
        self.workflowManager = workflowManager
        self.projectSelection = projectSelection
    }

    // MARK: - Computed

    var workflowFileNames: [String] {
        workflows.map(\.fileName)
    }

    var canAddCandidate: Bool {
        !workflowFileNames.isEmpty
    }

    /// True when the Save button should be enabled.
    var canSave: Bool {
        !isSaving
    }

    // MARK: - Project selection

    /// Updates the selected project path and persists it via the shared selection.
    func setSelectedProject(_ path: String?) {
        projectSelection.selectedPath = path
    }

    // MARK: - Workflows

    /// Reloads the workflow list from the selected project's `.zenflow/workflows/` directory.
    func refreshWorkflows() {
        guard let path = projectSelection.selectedPath else {
            workflows = []
            return
        }
        workflows = workflowManager.loadWorkflows(from: path)
    }

    // MARK: - Config load / save

    /// Loads the persisted router config from disk into the editable state.
    /// If no config is saved yet, resets to defaults.
    func loadFromConfig() {
        routerManager.loadConfig()
        if let config = routerManager.config {
            enabled = config.enabled
            classifier = config.classifier
            threshold = config.threshold
            defaultWorkflow = config.defaultWorkflow
            cache = config.cache
            candidates = config.candidates
        } else {
            resetToDefaults()
        }
    }

    /// Resets all editable state to fresh defaults (no persisted config).
    func resetToDefaults() {
        enabled = false
        classifier = availableModelSlugs.first ?? ""
        threshold = 0.75
        defaultWorkflow = workflowFileNames.first ?? ""
        cache = true
        candidates = []
    }

    /// Refreshes workflows and reloads config from disk.
    /// Used by the Refresh button and the initial on-appear path.
    func refresh() {
        refreshWorkflows()
        loadFromConfig()
    }

    /// Discards in-memory changes by reloading the persisted config.
    func discard() {
        loadFromConfig()
    }

    /// Persists the current state to disk.
    /// - Returns: `true` on success, `false` on validation or save failure.
    @discardableResult
    func save() -> Bool {
        isSaving = true
        defer { isSaving = false }
        saveError = nil

        if enabled && candidates.count < 2 {
            saveError = "Add at least 2 candidates."
            return false
        }
        if enabled && classifier.isEmpty {
            saveError = "Select a classifier model."
            return false
        }
        if enabled && defaultWorkflow.isEmpty {
            saveError = "Select a default fallback workflow."
            return false
        }

        let config = ZenflowRouterConfig(
            enabled: enabled,
            classifier: classifier,
            threshold: threshold,
            defaultWorkflow: defaultWorkflow,
            cache: cache,
            candidates: candidates
        )

        do {
            try routerManager.saveConfig(config)
            return true
        } catch let error as ZenflowRouterManager.ValidationError {
            saveError = error.localizedDescription
            return false
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    // MARK: - Candidates

    /// Appends a new candidate pre-populated with the first available workflow.
    /// No-op when there are no workflows available to reference.
    func addCandidate() {
        guard let first = workflowFileNames.first else { return }
        candidates.append(ZenflowRouterCandidate(
            workflowFileName: first,
            cost: 1.0,
            quality: 2.0,
            card: ""
        ))
    }

    /// Removes a candidate by its workflow file name.
    func removeCandidate(_ candidate: ZenflowRouterCandidate) {
        candidates.removeAll { $0.workflowFileName == candidate.workflowFileName }
    }
}
