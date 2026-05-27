import XCTest
@testable import Shimbar

final class ProcessRunnerTests: XCTestCase {
    
    func testProcessRunnerDirectExecution() async {
        do {
            let result = try await ProcessRunner.run("/bin/echo", arguments: ["test-process-runner"])
            XCTAssertTrue(result.succeeded, "Direct binary execution of echo should succeed")
            XCTAssertEqual(result.stdout, "test-process-runner", "Echo output should be captured")
            XCTAssertEqual(result.exitCode, 0, "Exit code should be 0")
        } catch {
            XCTFail("Direct binary execution of /bin/echo failed with: \(error)")
        }
    }
    
    func testProcessRunnerFailure() async {
        do {
            let result = try await ProcessRunner.run("/usr/bin/false")
            XCTAssertFalse(result.succeeded, "Executable false should exit with failure status")
            XCTAssertEqual(result.exitCode, 1, "Exit code should be 1")
        } catch {
            XCTFail("ProcessRunner should capture exit codes of failed processes cleanly without throwing")
        }
    }
}
