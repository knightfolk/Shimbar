import XCTest
@testable import Shimbar

final class AutoRouterForceReclassifyButtonTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoRouterForceReclassifyTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRouterCacheResetDeletesFile() {
        let cacheFile = tempDir.appendingPathComponent("router-cache.json")
        let data = """
        {"hash1": {"selected_workflow": "a", "confidence": 0.9, "expires_at": 9999999999.0}}
        """.data(using: .utf8)!
        try? data.write(to: cacheFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))

        let originalURL = RouterCache.cacheURL
        XCTAssertFalse(RouterCache.exists)
    }

    func testRouterCacheResetDoesNotThrowWhenFileMissing() {
        let missingURL = tempDir.appendingPathComponent("nonexistent-cache.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))

        RouterCache.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
    }

    func testRouterCacheResetClearsExistingCache() {
        let zenflowDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zenflow")
        if !FileManager.default.fileExists(atPath: zenflowDir.path) {
            try? FileManager.default.createDirectory(at: zenflowDir, withIntermediateDirectories: true)
        }

        let cacheFile = RouterCache.cacheURL
        let existed = FileManager.default.fileExists(atPath: cacheFile.path)
        if !existed {
            let data = "{}".data(using: .utf8)!
            try? data.write(to: cacheFile)
        }

        RouterCache.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: RouterCache.cacheURL.path))

        if !existed {
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }

    func testModelsJsonManagerDropRouterCache() {
        let cacheFile = RouterCache.cacheURL
        let existed = FileManager.default.fileExists(atPath: cacheFile.path)
        if !existed {
            let zenflowDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".zenflow")
            if !FileManager.default.fileExists(atPath: zenflowDir.path) {
                try? FileManager.default.createDirectory(at: zenflowDir, withIntermediateDirectories: true)
            }
            let data = "{}".data(using: .utf8)!
            try? data.write(to: cacheFile)
        }

        ModelsJsonManager.shared.regenerateCatalogAndConfig()
        XCTAssertFalse(FileManager.default.fileExists(atPath: RouterCache.cacheURL.path))
    }
}
