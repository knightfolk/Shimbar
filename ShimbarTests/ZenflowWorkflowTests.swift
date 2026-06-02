import XCTest
@testable import Shimbar

final class ZenflowWorkflowTests: XCTestCase {

    func testExtractTitleFromMarkdown() {
        let markdown = "# My Workflow Title\n\nSome content here"
        XCTAssertEqual(ZenflowWorkflow.extractTitle(from: markdown), "My Workflow Title")
    }

    func testExtractTitleWithExtraWhitespace() {
        let markdown = "   #   Spaced Title  \n\nContent"
        XCTAssertEqual(ZenflowWorkflow.extractTitle(from: markdown), "Spaced Title")
    }

    func testExtractTitleReturnsNilWhenNoH1() {
        let markdown = "## H2 Header\n\n### H3 Header"
        XCTAssertNil(ZenflowWorkflow.extractTitle(from: markdown))
    }

    func testExtractTitleFromEmptyString() {
        XCTAssertNil(ZenflowWorkflow.extractTitle(from: ""))
    }

    func testExtractTitleOnlyPicksFirstH1() {
        let markdown = "# First Title\n\n# Second Title"
        XCTAssertEqual(ZenflowWorkflow.extractTitle(from: markdown), "First Title")
    }

    func testAbsolutePathResolvesCorrectly() {
        let workflow = ZenflowWorkflow(
            fileName: "test-workflow.md",
            title: "Test",
            content: "# Test",
            projectPath: "/Users/test/project"
        )

        let expected = "/Users/test/project/.zenflow/workflows/test-workflow.md"
        XCTAssertEqual(workflow.absolutePath.path, expected)
    }

    func testIdIsStableUUID() {
        let id = UUID()
        let workflow = ZenflowWorkflow(id: id, fileName: "test.md", title: "Test", content: "", projectPath: "/test")
        XCTAssertEqual(workflow.id, id)
    }

    func testHashableAndEquatable() {
        let id = UUID()
        let w1 = ZenflowWorkflow(id: id, fileName: "a.md", title: "A", content: "c", projectPath: "/p")
        let w2 = ZenflowWorkflow(id: id, fileName: "a.md", title: "A", content: "c", projectPath: "/p")
        let w3 = ZenflowWorkflow(id: UUID(), fileName: "b.md", title: "B", content: "d", projectPath: "/p")

        XCTAssertEqual(w1, w2)
        XCTAssertNotEqual(w1, w3)
    }
}
