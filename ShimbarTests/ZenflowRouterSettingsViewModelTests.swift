import XCTest
@testable import Shimbar

@MainActor
final class ZenflowRouterSettingsViewModelTests: XCTestCase {

    private var tempProjectDir: URL!
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var workflowManager: ZenflowWorkflowManager!
    private var projectSelection: ZenflowProjectSelection!
    private var routerManager: ZenflowRouterManager!
    private var viewModel: ZenflowRouterSettingsViewModel!

    override func setUp() async throws {
        try await super.setUp()

        suiteName = "com.shimbar.tests.router.vm.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        workflowManager = ZenflowWorkflowManager(defaults: testDefaults)
        projectSelection = ZenflowProjectSelection(workflowManager: workflowManager)
        routerManager = ZenflowRouterManager.shared

        // Clean up any prior state on the shared router manager
        try? routerManager.deleteConfig()
        routerManager.clearCache()
        routerManager.clearDecisionLog()

        let fm = FileManager.default
        tempProjectDir = fm.temporaryDirectory.appendingPathComponent("ZenflowRouterVMTest-\(UUID().uuidString)")
        try fm.createDirectory(at: tempProjectDir, withIntermediateDirectories: true)

        viewModel = ZenflowRouterSettingsViewModel(
            routerManager: routerManager,
            workflowManager: workflowManager,
            projectSelection: projectSelection
        )
        viewModel.availableModelSlugs = ["gpt-4o", "claude-sonnet-4"]
    }

    override func tearDown() async throws {
        try? routerManager.deleteConfig()
        routerManager.clearCache()
        routerManager.clearDecisionLog()

        let fm = FileManager.default
        if fm.fileExists(atPath: tempProjectDir.path) {
            try fm.removeItem(at: tempProjectDir)
        }
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        workflowManager = nil
        projectSelection = nil
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - Initial state

    func testInitialStateDefaults() {
        XCTAssertFalse(viewModel.enabled)
        XCTAssertEqual(viewModel.threshold, 0.75)
        XCTAssertTrue(viewModel.cache)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertNil(viewModel.saveError)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertTrue(viewModel.workflows.isEmpty)
    }

    func testCanAddCandidateDisabledWhenNoWorkflows() {
        XCTAssertFalse(viewModel.canAddCandidate)
    }

    func testCanAddCandidateEnabledWhenWorkflowsPresent() throws {
        try writeWorkflow(fileName: "review.md", title: "Review")
        viewModel.setSelectedProject(tempProjectDir.path)
        viewModel.refreshWorkflows()

        XCTAssertTrue(viewModel.canAddCandidate)
    }

    // MARK: - setSelectedProject

    func testSetSelectedProjectUpdatesSharedSelection() {
        viewModel.setSelectedProject(tempProjectDir.path)
        XCTAssertEqual(projectSelection.selectedPath, tempProjectDir.path)
    }

    func testSetSelectedProjectToNilClearsSelection() {
        viewModel.setSelectedProject(tempProjectDir.path)
        viewModel.setSelectedProject(nil)
        XCTAssertNil(projectSelection.selectedPath)
    }

    // MARK: - refreshWorkflows

    func testRefreshWorkflowsLoadsFromSelectedProject() throws {
        try writeWorkflow(fileName: "alpha.md", title: "Alpha")
        try writeWorkflow(fileName: "beta.md", title: "Beta")

        viewModel.setSelectedProject(tempProjectDir.path)
        viewModel.refreshWorkflows()

        XCTAssertEqual(viewModel.workflows.count, 2)
        XCTAssertEqual(Set(viewModel.workflowFileNames), Set(["alpha.md", "beta.md"]))
    }

    func testRefreshWorkflowsWithNoProjectClearsList() throws {
        try writeWorkflow(fileName: "alpha.md", title: "Alpha")
        viewModel.setSelectedProject(tempProjectDir.path)
        viewModel.refreshWorkflows()
        XCTAssertEqual(viewModel.workflows.count, 1)

        viewModel.setSelectedProject(nil)
        viewModel.refreshWorkflows()
        XCTAssertTrue(viewModel.workflows.isEmpty)
    }

    // MARK: - loadFromConfig

    func testLoadFromConfigPopulatesStateFromSavedConfig() throws {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.85,
            defaultWorkflow: "code-review.md",
            cache: false,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "code-review.md", cost: 1.0, quality: 3.0, card: "Review"),
                ZenflowRouterCandidate(workflowFileName: "security-audit.md", cost: 2.5, quality: 5.0, card: "Security")
            ]
        )
        try routerManager.saveConfig(config)

        viewModel.loadFromConfig()

        XCTAssertTrue(viewModel.enabled)
        XCTAssertEqual(viewModel.classifier, "gpt-4o")
        XCTAssertEqual(viewModel.threshold, 0.85)
        XCTAssertEqual(viewModel.defaultWorkflow, "code-review.md")
        XCTAssertFalse(viewModel.cache)
        XCTAssertEqual(viewModel.candidates.count, 2)
    }

    func testLoadFromConfigResetsWhenNoConfigExists() {
        XCTAssertNil(routerManager.config)

        viewModel.loadFromConfig()

        XCTAssertFalse(viewModel.enabled)
        XCTAssertEqual(viewModel.threshold, 0.75)
        XCTAssertTrue(viewModel.cache)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        // Classifier should default to first available slug
        XCTAssertEqual(viewModel.classifier, "gpt-4o")
    }

    func testLoadFromConfigUsesFirstWorkflowAsDefaultWhenNoConfig() throws {
        try writeWorkflow(fileName: "alpha.md", title: "Alpha")
        viewModel.setSelectedProject(tempProjectDir.path)
        viewModel.refreshWorkflows()

        viewModel.loadFromConfig()

        XCTAssertEqual(viewModel.defaultWorkflow, "alpha.md")
    }

    // MARK: - save

    func testSavePersistsConfigToDisk() throws {
        viewModel.enabled = true
        viewModel.classifier = "gpt-4o"
        viewModel.defaultWorkflow = "alpha.md"
        viewModel.threshold = 0.6
        viewModel.cache = true
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A"),
            ZenflowRouterCandidate(workflowFileName: "beta.md", cost: 2.0, quality: 3.0, card: "B")
        ]

        let result = viewModel.save()

        XCTAssertTrue(result)
        XCTAssertNil(viewModel.saveError)
        XCTAssertNotNil(routerManager.config)
        XCTAssertEqual(routerManager.config?.classifier, "gpt-4o")
        XCTAssertEqual(routerManager.config?.threshold, 0.6)
        XCTAssertEqual(routerManager.config?.candidates.count, 2)
    }

    func testSaveFailsWithTooFewCandidates() {
        viewModel.enabled = true
        viewModel.classifier = "gpt-4o"
        viewModel.defaultWorkflow = "alpha.md"
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A")
        ]

        let result = viewModel.save()

        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.saveError, "Add at least 2 candidates.")
    }

    func testSaveFailsWithoutClassifier() {
        viewModel.enabled = true
        viewModel.classifier = ""
        viewModel.defaultWorkflow = "alpha.md"
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A"),
            ZenflowRouterCandidate(workflowFileName: "beta.md", cost: 2.0, quality: 3.0, card: "B")
        ]

        let result = viewModel.save()

        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.saveError, "Select a classifier model.")
    }

    func testSaveFailsWithoutDefaultWorkflow() {
        viewModel.enabled = true
        viewModel.classifier = "gpt-4o"
        viewModel.defaultWorkflow = ""
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A"),
            ZenflowRouterCandidate(workflowFileName: "beta.md", cost: 2.0, quality: 3.0, card: "B")
        ]

        let result = viewModel.save()

        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.saveError, "Select a default fallback workflow.")
    }

    func testSaveDisabledConfigSkipsValidation() {
        viewModel.enabled = false
        viewModel.classifier = ""
        viewModel.defaultWorkflow = ""
        viewModel.candidates = []

        let result = viewModel.save()

        XCTAssertTrue(result, "Disabled config should not require candidates/classifier/default")
        XCTAssertNil(viewModel.saveError)
    }

    func testSaveTogglesIsSavingAroundSave() throws {
        viewModel.enabled = true
        viewModel.classifier = "gpt-4o"
        viewModel.defaultWorkflow = "alpha.md"
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A"),
            ZenflowRouterCandidate(workflowFileName: "beta.md", cost: 2.0, quality: 3.0, card: "B")
        ]

        let result = viewModel.save()

        XCTAssertTrue(result)
        XCTAssertFalse(viewModel.isSaving, "isSaving should reset to false after save completes")
    }

    func testSaveClearsPreviousErrorOnSuccess() throws {
        viewModel.saveError = "Some prior error"
        viewModel.enabled = true
        viewModel.classifier = "gpt-4o"
        viewModel.defaultWorkflow = "alpha.md"
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A"),
            ZenflowRouterCandidate(workflowFileName: "beta.md", cost: 2.0, quality: 3.0, card: "B")
        ]

        let result = viewModel.save()

        XCTAssertTrue(result)
        XCTAssertNil(viewModel.saveError, "saveError should be cleared on a successful save")
    }

    // MARK: - discard

    func testDiscardRevertsInMemoryChangesToPersistedConfig() throws {
        let config = ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.55,
            defaultWorkflow: "code-review.md",
            cache: false,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "code-review.md", cost: 1.0, quality: 3.0, card: "Review"),
                ZenflowRouterCandidate(workflowFileName: "security-audit.md", cost: 2.5, quality: 5.0, card: "Security")
            ]
        )
        try routerManager.saveConfig(config)

        viewModel.loadFromConfig()
        // Simulate the user making changes
        viewModel.threshold = 0.99
        viewModel.classifier = "claude-sonnet-4"
        viewModel.candidates.append(ZenflowRouterCandidate(workflowFileName: "x.md", cost: 1.0, quality: 1.0, card: ""))

        viewModel.discard()

        XCTAssertEqual(viewModel.threshold, 0.55)
        XCTAssertEqual(viewModel.classifier, "gpt-4o")
        XCTAssertEqual(viewModel.candidates.count, 2)
    }

    // MARK: - refresh

    func testRefreshReloadsWorkflowsAndConfig() throws {
        try writeWorkflow(fileName: "alpha.md", title: "Alpha")
        viewModel.setSelectedProject(tempProjectDir.path)
        viewModel.refreshWorkflows()
        XCTAssertEqual(viewModel.workflows.count, 1)

        // Add a new workflow file on disk
        try writeWorkflow(fileName: "beta.md", title: "Beta")

        // Persist a config so we can verify it's reloaded
        try routerManager.saveConfig(ZenflowRouterConfig(
            enabled: true,
            classifier: "gpt-4o",
            threshold: 0.42,
            defaultWorkflow: "alpha.md",
            cache: true,
            candidates: [
                ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A"),
                ZenflowRouterCandidate(workflowFileName: "beta.md", cost: 2.0, quality: 3.0, card: "B")
            ]
        ))

        viewModel.refresh()

        XCTAssertEqual(viewModel.workflows.count, 2, "refresh should re-scan the workflows directory")
        XCTAssertEqual(viewModel.threshold, 0.42, "refresh should reload config from disk")
    }

    // MARK: - addCandidate / removeCandidate

    func testAddCandidateAppendsWithDefaults() throws {
        try writeWorkflow(fileName: "alpha.md", title: "Alpha")
        try writeWorkflow(fileName: "beta.md", title: "Beta")
        viewModel.setSelectedProject(tempProjectDir.path)
        viewModel.refreshWorkflows()

        XCTAssertTrue(viewModel.candidates.isEmpty)

        viewModel.addCandidate()

        XCTAssertEqual(viewModel.candidates.count, 1)
        XCTAssertEqual(viewModel.candidates.first?.workflowFileName, "alpha.md")
        XCTAssertEqual(viewModel.candidates.first?.cost, 1.0)
        XCTAssertEqual(viewModel.candidates.first?.quality, 2.0)
        XCTAssertEqual(viewModel.candidates.first?.card, "")
    }

    func testAddCandidateIsNoOpWhenNoWorkflows() {
        XCTAssertTrue(viewModel.workflows.isEmpty)

        viewModel.addCandidate()

        XCTAssertTrue(viewModel.candidates.isEmpty)
    }

    func testRemoveCandidateRemovesByWorkflowFileName() {
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A"),
            ZenflowRouterCandidate(workflowFileName: "beta.md", cost: 2.0, quality: 3.0, card: "B"),
            ZenflowRouterCandidate(workflowFileName: "gamma.md", cost: 3.0, quality: 4.0, card: "G")
        ]

        let target = viewModel.candidates[1]
        viewModel.removeCandidate(target)

        XCTAssertEqual(viewModel.candidates.count, 2)
        XCTAssertFalse(viewModel.candidates.contains { $0.workflowFileName == "beta.md" })
    }

    func testRemoveCandidateNotPresentIsNoOp() {
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A")
        ]
        let ghost = ZenflowRouterCandidate(workflowFileName: "missing.md", cost: 1.0, quality: 1.0, card: "")

        viewModel.removeCandidate(ghost)

        XCTAssertEqual(viewModel.candidates.count, 1)
    }

    // MARK: - resetToDefaults

    func testResetToDefaultsClearsAllFields() {
        viewModel.enabled = true
        viewModel.classifier = "gpt-4o"
        viewModel.threshold = 0.5
        viewModel.defaultWorkflow = "alpha.md"
        viewModel.cache = false
        viewModel.candidates = [
            ZenflowRouterCandidate(workflowFileName: "alpha.md", cost: 1.0, quality: 2.0, card: "A")
        ]

        viewModel.resetToDefaults()

        XCTAssertFalse(viewModel.enabled)
        XCTAssertEqual(viewModel.classifier, "gpt-4o", "Classifier should default to first available slug")
        XCTAssertEqual(viewModel.threshold, 0.75)
        XCTAssertTrue(viewModel.cache)
        XCTAssertTrue(viewModel.candidates.isEmpty)
    }

    // MARK: - canSave

    func testCanSaveDefaultsTrue() {
        XCTAssertTrue(viewModel.canSave)
    }

    func testCanSaveFalseWhileSaving() {
        viewModel.isSaving = true
        XCTAssertFalse(viewModel.canSave)
    }

    // MARK: - Helpers

    private func writeWorkflow(fileName: String, title: String) throws {
        let workflowsDir = tempProjectDir.appendingPathComponent(".zenflow/workflows")
        try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
        let content = "# \(title)\n\nWorkflow content for \(fileName)\n"
        try content.write(to: workflowsDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
    }
}
