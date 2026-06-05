import Observation

// MARK: - ZenflowProjectSelection

/// Shared observable state for the selected project path used by Zenflow features.
/// Both `ZencoderSettingsTab` (workflows) and `ZenflowRouterSettingsTab` use this
/// to stay in sync without duplicating state.
@Observable
final class ZenflowProjectSelection {
    static let shared = ZenflowProjectSelection()

    var selectedPath: String? {
        didSet {
            guard selectedPath != oldValue else { return }
            if let path = selectedPath {
                workflowManager.addRecentProject(path)
            }
        }
    }

    private let workflowManager: ZenflowWorkflowManager

    init(workflowManager: ZenflowWorkflowManager = .shared) {
        self.workflowManager = workflowManager
        self.selectedPath = workflowManager.recentProjects.first
    }
}
