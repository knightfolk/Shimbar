import XCTest
@testable import Shimbar

final class ZenflowWorkflowManagerTests: XCTestCase {

    private var tempProjectDir: URL!
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var manager: ZenflowWorkflowManager!

    override func setUp() async throws {
        try await super.setUp()

        suiteName = "com.shimbar.tests.zenflow.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        manager = ZenflowWorkflowManager(defaults: testDefaults)

        let fm = FileManager.default
        tempProjectDir = fm.temporaryDirectory.appendingPathComponent("ZenflowTestProject-\(UUID().uuidString)")
        try fm.createDirectory(at: tempProjectDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: tempProjectDir.path) {
            try fm.removeItem(at: tempProjectDir)
        }
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        manager = nil
        try await super.tearDown()
    }

    func testLoadWorkflowsFromEmptyDirectory() {
        let workflows = manager.loadWorkflows(from: tempProjectDir.path)
        XCTAssertTrue(workflows.isEmpty, "No workflows directory means empty result")
    }

    func testLoadWorkflowsFromDirectoryWithNoWorkflows() throws {
        let workflowsDir = tempProjectDir.appendingPathComponent(".zenflow/workflows")
        try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
        let workflows = manager.loadWorkflows(from: tempProjectDir.path)
        XCTAssertTrue(workflows.isEmpty)
    }

    func testSaveAndLoadWorkflow() throws {
        let workflow = ZenflowWorkflow(
            fileName: "test.md",
            title: "Test Workflow",
            content: "# Test Workflow\n\nStep 1: Do something",
            projectPath: tempProjectDir.path
        )

        _ = try manager.saveWorkflow(workflow)

        let loaded = manager.loadWorkflows(from: tempProjectDir.path)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Test Workflow")
        XCTAssertEqual(loaded[0].fileName, "test.md")
        XCTAssertTrue(loaded[0].content.contains("Step 1"))
    }

    func testDeleteWorkflow() throws {
        let workflow = ZenflowWorkflow(
            fileName: "delete-me.md",
            title: "Delete Me",
            content: "# Delete Me",
            projectPath: tempProjectDir.path
        )

        try manager.saveWorkflow(workflow)
        var loaded = manager.loadWorkflows(from: tempProjectDir.path)
        XCTAssertEqual(loaded.count, 1)

        try manager.deleteWorkflow(workflow)
        loaded = manager.loadWorkflows(from: tempProjectDir.path)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testRecentProjectsTracking() throws {
        let path = tempProjectDir.path

        manager.addRecentProject(path)
        XCTAssertTrue(manager.recentProjects.contains(path))

        manager.addRecentProject(path)
        let count = manager.recentProjects.filter { $0 == path }.count
        XCTAssertEqual(count, 1, "Same project should not be duplicated in recent list")
    }

    func testRecentProjectsMaxLimit() {
        for i in 0..<15 {
            manager.addRecentProject("/tmp/shimbar-test-fake-\(UUID().uuidString)-\(i)")
        }
        XCTAssertLessThanOrEqual(manager.recentProjects.count, 10, "Recent projects should be capped at 10")
    }

    func testRecentProjectsMovesToTop() {
        let projectA = "/tmp/shimbar-test-a-\(UUID().uuidString)"
        let projectB = "/tmp/shimbar-test-b-\(UUID().uuidString)"
        manager.addRecentProject(projectA)
        manager.addRecentProject(projectB)
        manager.addRecentProject(projectA)

        XCTAssertEqual(manager.recentProjects.first, projectA, "Re-added project should move to top")
    }

    func testLoadWorkflowsSortedByTitle() throws {
        let workflowsDir = tempProjectDir.appendingPathComponent(".zenflow/workflows")
        try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)

        try "# Zebra Workflow\ncontent".write(to: workflowsDir.appendingPathComponent("z.md"), atomically: true, encoding: .utf8)
        try "# Alpha Workflow\ncontent".write(to: workflowsDir.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let loaded = manager.loadWorkflows(from: tempProjectDir.path)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].title, "Alpha Workflow")
        XCTAssertEqual(loaded[1].title, "Zebra Workflow")
    }

    func testNonMarkdownFilesIgnored() throws {
        let workflowsDir = tempProjectDir.appendingPathComponent(".zenflow/workflows")
        try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)

        try "# Valid".write(to: workflowsDir.appendingPathComponent("valid.md"), atomically: true, encoding: .utf8)
        try "not markdown".write(to: workflowsDir.appendingPathComponent("ignore.txt"), atomically: true, encoding: .utf8)
        try "json".write(to: workflowsDir.appendingPathComponent("ignore.json"), atomically: true, encoding: .utf8)

        let loaded = manager.loadWorkflows(from: tempProjectDir.path)
        XCTAssertEqual(loaded.count, 1, "Only .md files should be loaded")
        XCTAssertEqual(loaded[0].title, "Valid")
    }
}
