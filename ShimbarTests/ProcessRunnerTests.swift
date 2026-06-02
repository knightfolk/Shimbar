import XCTest
@testable import Shimbar

final class ProcessRunnerTests: XCTestCase {

    func testProcessRunnerEcho() async {
        do {
            let result = try await ProcessRunner.run("/bin/echo", arguments: ["hello world"])
            XCTAssertTrue(result.succeeded)
            XCTAssertEqual(result.stdout, "hello world")
            XCTAssertTrue(result.stderr.isEmpty)
        } catch {
            XCTFail("Echo should succeed: \(error)")
        }
    }

    func testProcessRunnerCatWithInput() async {
        do {
            let result = try await ProcessRunner.run("/bin/cat", arguments: ["/dev/null"])
            XCTAssertTrue(result.succeeded)
            XCTAssertEqual(result.stdout, "")
        } catch {
            XCTFail("Cat /dev/null should succeed: \(error)")
        }
    }

    func testProcessRunnerStderr() async {
        do {
            let result = try await ProcessRunner.run("/bin/bash", arguments: ["-c", "echo error >&2"])
            XCTAssertTrue(result.succeeded)
            XCTAssertEqual(result.stderr, "error")
        } catch {
            XCTFail("Should capture stderr: \(error)")
        }
    }

    func testProcessRunnerNonexistentCommand() async {
        do {
            let result = try await ProcessRunner.run("/nonexistent/command_xyz_12345")
            XCTAssertFalse(result.succeeded, "Nonexistent command should fail")
        } catch {
            // Expected: command not found throws or returns non-zero
        }
    }

    func testProcessResultProperties() {
        let success = ProcessResult(exitCode: 0, stdout: "out", stderr: "err")
        XCTAssertTrue(success.succeeded)
        XCTAssertEqual(success.exitCode, 0)

        let failure = ProcessResult(exitCode: 1, stdout: "", stderr: "bad")
        XCTAssertFalse(failure.succeeded)
        XCTAssertEqual(failure.exitCode, 1)
    }

    func testProcessRunnerWhichEcho() async {
        let path = await ProcessRunner.which("echo")
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.contains("echo"))
    }

    func testProcessRunnerWhichNonexistent() async {
        let path = await ProcessRunner.which("nonexistent_binary_that_does_not_exist_12345")
        XCTAssertNil(path)
    }

    func testProcessRunnerExitCode() async {
        do {
            let result = try await ProcessRunner.run("/bin/bash", arguments: ["-c", "exit 42"])
            XCTAssertFalse(result.succeeded)
            XCTAssertEqual(result.exitCode, 42)
        } catch {
            XCTFail("Non-zero exit should be captured, not thrown: \(error)")
        }
    }

    func testProcessRunnerLargeOutput() async {
        do {
            let result = try await ProcessRunner.run("/usr/bin/seq", arguments: ["1000"])
            XCTAssertTrue(result.succeeded)
            let lines = result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
            XCTAssertEqual(lines.count, 1000)
        } catch {
            XCTFail("seq should handle large output: \(error)")
        }
    }

    func testProcessRunnerUnicodeOutput() async {
        do {
            let result = try await ProcessRunner.run("/bin/echo", arguments: ["Hello 🌍 世界"])
            XCTAssertTrue(result.succeeded)
            XCTAssertTrue(result.stdout.contains("Hello 🌍 世界"))
        } catch {
            XCTFail("Unicode echo should work: \(error)")
        }
    }
}
