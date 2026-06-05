import XCTest
@testable import Shimbar

final class ZenflowProjectSelectionTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var workflowManager: ZenflowWorkflowManager!

    override func setUp() async throws {
        try await super.setUp()

        suiteName = "com.shimbar.tests.projectselection.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        workflowManager = ZenflowWorkflowManager(defaults: testDefaults)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        workflowManager = nil
        try await super.tearDown()
    }

    // MARK: - Initialization

    func testInitSeedsSelectedPathFromMostRecentProject() {
        workflowManager.addRecentProject("/path/a")
        workflowManager.addRecentProject("/path/b")

        let selection = ZenflowProjectSelection(workflowManager: workflowManager)

        XCTAssertEqual(selection.selectedPath, "/path/b", "Should pick most recent project (head of recents list)")
    }

    func testInitWithNoRecentProjectsLeavesSelectedPathNil() {
        let selection = ZenflowProjectSelection(workflowManager: workflowManager)

        XCTAssertNil(selection.selectedPath, "No recent projects means nothing selected")
    }

    func testInitDoesNotReAddInitialPathToRecents() {
        workflowManager.addRecentProject("/path/seed")

        _ = ZenflowProjectSelection(workflowManager: workflowManager)

        XCTAssertEqual(workflowManager.recentProjects, ["/path/seed"], "Init should not mutate recent projects")
    }

    // MARK: - didSet side effects

    func testSettingSelectedPathAddsToRecents() {
        let selection = ZenflowProjectSelection(workflowManager: workflowManager)

        selection.selectedPath = "/new/project"

        XCTAssertTrue(workflowManager.recentProjects.contains("/new/project"))
    }

    func testSettingSelectedPathMovesItToTop() {
        workflowManager.addRecentProject("/old/a")
        workflowManager.addRecentProject("/old/b")
        let selection = ZenflowProjectSelection(workflowManager: workflowManager)

        selection.selectedPath = "/old/a"

        XCTAssertEqual(workflowManager.recentProjects.first, "/old/a")
    }

    func testSettingSelectedPathToSameValueIsNoOp() {
        let selection = ZenflowProjectSelection(workflowManager: workflowManager)
        selection.selectedPath = "/p1"

        let recentsBefore = workflowManager.recentProjects
        let positionBefore = recentsBefore.firstIndex(of: "/p1")

        selection.selectedPath = "/p1"
        let recentsAfter = workflowManager.recentProjects
        let positionAfter = recentsAfter.firstIndex(of: "/p1")

        XCTAssertEqual(recentsBefore, recentsAfter, "Re-assigning the same path should not mutate recents")
        XCTAssertEqual(positionBefore, positionAfter, "Re-assigning the same path should not move it in the recents list")
    }

    func testSettingSelectedPathToNilDoesNotAddToRecents() {
        workflowManager.addRecentProject("/p1")
        let selection = ZenflowProjectSelection(workflowManager: workflowManager)
        let countBefore = workflowManager.recentProjects.count

        selection.selectedPath = nil

        XCTAssertEqual(workflowManager.recentProjects.count, countBefore, "Clearing the selection should not add to recents")
    }

    // MARK: - Shared singleton

    func testSharedInstanceIsStable() {
        let a = ZenflowProjectSelection.shared
        let b = ZenflowProjectSelection.shared

        XCTAssertTrue(a === b, ".shared must always return the same instance")
    }

    func testSharedInstanceMutationsAreObservableAcrossReferences() {
        let selection = ZenflowProjectSelection.shared
        let oldPath = selection.selectedPath
        defer {
            selection.selectedPath = oldPath
        }

        let temp = "/shared/test/\(UUID().uuidString)"
        selection.selectedPath = temp

        XCTAssertEqual(ZenflowProjectSelection.shared.selectedPath, temp)
    }
}
