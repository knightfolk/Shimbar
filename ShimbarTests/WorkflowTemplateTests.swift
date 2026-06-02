import XCTest
@testable import Shimbar

final class WorkflowTemplateTests: XCTestCase {

    func testTemplatesExist() {
        XCTAssertFalse(WorkflowTemplate.templates.isEmpty)
    }

    func testDefaultFileNameMatchesId() {
        for template in WorkflowTemplate.templates {
            XCTAssertEqual(template.defaultFileName, "\(template.id).md")
        }
    }

    func testTemplatesHaveContent() {
        for template in WorkflowTemplate.templates {
            XCTAssertFalse(template.content.isEmpty, "Template \(template.id) should have content")
            XCTAssertTrue(template.content.hasPrefix("# "), "Template \(template.id) content should start with a title")
        }
    }

    func testTemplatesHaveTitles() {
        for template in WorkflowTemplate.templates {
            XCTAssertFalse(template.title.isEmpty, "Template \(template.id) should have a title")
        }
    }

    func testTemplatesHaveDescriptions() {
        for template in WorkflowTemplate.templates {
            XCTAssertFalse(template.description.isEmpty, "Template \(template.id) should have a description")
        }
    }

    func testTemplatesHaveUniqueIds() {
        let ids = WorkflowTemplate.templates.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Template IDs should be unique")
    }

    func testDedentRemovesCommonIndentation() {
        let input = "    line1\n    line2\n    line3"
        let result = WorkflowTemplate.dedent(input)
        XCTAssertEqual(result, "line1\nline2\nline3")
    }

    func testDedentPreservesRelativeIndentation() {
        let input = "    line1\n        indented\n    line3"
        let result = WorkflowTemplate.dedent(input)
        XCTAssertEqual(result, "line1\n    indented\nline3")
    }

    func testDedentNoIndentation() {
        let input = "line1\nline2\nline3"
        let result = WorkflowTemplate.dedent(input)
        XCTAssertEqual(result, "line1\nline2\nline3")
    }

    func testDedentAllWhitespaceLinesReturnsOriginal() {
        let input = "   \n  \n   "
        let result = WorkflowTemplate.dedent(input)
        XCTAssertEqual(result, input, "All-whitespace lines should return the original string unchanged")
    }
}
