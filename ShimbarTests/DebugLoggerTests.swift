import XCTest
@testable import Shimbar

final class DebugLoggerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DebugLoggerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testDebugLoggerDoesNotCrash() {
        DebugLogger.log("Test log entry from unit tests")
        DebugLogger.log("")
        DebugLogger.log(String(repeating: "a", count: 10000))
    }

    func testRotateIfNeededRemovesOversizedFile() throws {
        let logURL = tempDir.appendingPathComponent("test_debug.log")

        let largeContent = String(repeating: "x", count: Int(DebugLogger.maxLogSize) + 100)
        try largeContent.write(to: logURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))

        DebugLogger.rotateIfNeeded(logURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path), "Oversized log file should be rotated (removed)")
    }

    func testRotateIfNeededKeepsSmallFile() throws {
        let logURL = tempDir.appendingPathComponent("test_debug_small.log")

        try "small content".write(to: logURL, atomically: true, encoding: .utf8)

        DebugLogger.rotateIfNeeded(logURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path), "Small log file should not be rotated")
    }

    func testRotateIfNeededHandlesMissingFile() {
        let missingURL = tempDir.appendingPathComponent("nonexistent.log")
        DebugLogger.rotateIfNeeded(missingURL)
    }
}
