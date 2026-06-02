import XCTest
@testable import Shimbar

@MainActor
final class ShimUpdaterRepoResolutionTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        let fm = FileManager.default
        tempDir = fm.temporaryDirectory.appendingPathComponent("ShimUpdaterTest-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: tempDir.path) {
            try fm.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testResolveRepoPathFindsGitDir() async throws {
        let fm = FileManager.default
        let repoDir = tempDir.appendingPathComponent("codex-shim")
        let binDir = repoDir.appendingPathComponent("bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: repoDir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let binaryPath = binDir.appendingPathComponent("codex-shim").path

        let updater = ShimUpdater.shared
        let result = updater.resolveRepoPath(from: binaryPath)
        XCTAssertEqual(result, repoDir.path, "Should resolve repo root from binary inside bin/ directory")
    }

    func testResolveRepoPathWalksUpMultipleLevels() async throws {
        let fm = FileManager.default
        let repoDir = tempDir.appendingPathComponent("my-repo")
        let nestedBin = repoDir.appendingPathComponent("src/sub/pkg/bin")
        try fm.createDirectory(at: nestedBin, withIntermediateDirectories: true)
        try fm.createDirectory(at: repoDir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let binaryPath = nestedBin.appendingPathComponent("codex-shim").path

        let updater = ShimUpdater.shared
        let result = updater.resolveRepoPath(from: binaryPath)
        XCTAssertEqual(result, repoDir.path, "Should walk up multiple levels to find .git")
    }

    func testResolveRepoPathPrefersNearestGitAncestor() async throws {
        let fm = FileManager.default
        let outerRepo = tempDir.appendingPathComponent("outer-repo")
        let innerRepo = outerRepo.appendingPathComponent("inner-repo")
        let binDir = innerRepo.appendingPathComponent("bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: outerRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: innerRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let binaryPath = binDir.appendingPathComponent("codex-shim").path

        let updater = ShimUpdater.shared
        let result = updater.resolveRepoPath(from: binaryPath)
        XCTAssertEqual(result, innerRepo.path, "Should resolve the nearest .git ancestor, not the outer one")
    }
}
