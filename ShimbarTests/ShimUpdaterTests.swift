import XCTest
@testable import Shimbar

final class ShimUpdaterTests: XCTestCase {
    
    private var tempRepoURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a unique temporary directory for the git repository
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempRepoURL = tempDir
        
        // Initialize git repo
        _ = try await runGit(["init"])
        _ = try await runGit(["config", "user.name", "Test User"])
        _ = try await runGit(["config", "user.email", "test@example.com"])
        _ = try await runGit(["config", "commit.gpgsign", "false"])
    }
    
    override func tearDown() async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: tempRepoURL.path) {
            try fm.removeItem(at: tempRepoURL)
        }
        try await super.tearDown()
    }
    
    private func runGit(_ args: [String]) async throws -> ProcessResult {
        return try await ProcessRunner.run("/usr/bin/git", arguments: ["-C", tempRepoURL.path] + args)
    }
    
    func testGitAncestryAndObjectExistenceCommands() async throws {
        // 1. Create initial file and commit A
        let fileURL = tempRepoURL.appendingPathComponent("file.txt")
        try "initial content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        _ = try await runGit(["add", "file.txt"])
        _ = try await runGit(["commit", "-m", "Commit A"])
        
        let hashAResult = try await runGit(["rev-parse", "HEAD"])
        let hashA = hashAResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(hashA.isEmpty)
        
        // 2. Create another commit B on main
        try "updated content".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try await runGit(["add", "file.txt"])
        _ = try await runGit(["commit", "-m", "Commit B"])
        
        let hashBResult = try await runGit(["rev-parse", "HEAD"])
        let hashB = hashBResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(hashB.isEmpty)
        XCTAssertNotEqual(hashA, hashB)
        
        // 3. Test cat-file -e (object existence)
        // Both hashA and hashB should exist
        let existsA = try await runGit(["cat-file", "-e", hashA])
        XCTAssertTrue(existsA.succeeded, "Commit A should exist in the repository")
        
        let existsB = try await runGit(["cat-file", "-e", hashB])
        XCTAssertTrue(existsB.succeeded, "Commit B should exist in the repository")
        
        let existsFake = try await runGit(["cat-file", "-e", "0000000000000000000000000000000000000000"])
        XCTAssertFalse(existsFake.succeeded, "Fake hash should not exist in the repository")
        
        // 4. Test merge-base --is-ancestor
        // Commit A is ancestor of Commit B (since B was made after A on the same branch)
        // So merge-base --is-ancestor A B should succeed (exit code 0)
        let isAAncestorOfB = try await runGit(["merge-base", "--is-ancestor", hashA, hashB])
        XCTAssertTrue(isAAncestorOfB.succeeded, "Commit A should be an ancestor of Commit B")
        
        // Commit B is NOT an ancestor of Commit A
        // So merge-base --is-ancestor B A should fail (exit code 1)
        let isBAncestorOfA = try await runGit(["merge-base", "--is-ancestor", hashB, hashA])
        XCTAssertFalse(isBAncestorOfA.succeeded, "Commit B should NOT be an ancestor of Commit A")
    }
}
