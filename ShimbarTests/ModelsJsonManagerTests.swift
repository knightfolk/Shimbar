import XCTest
@testable import Shimbar

final class ModelsJsonManagerTests: XCTestCase {
    
    func testManagerInitialization() {
        let manager = ModelsJsonManager.shared
        XCTAssertNotNil(manager.modelsJsonURL)
        XCTAssertTrue(manager.modelsJsonURL.path.contains(".codex-shim/models.json"), "Path should point inside the user's home directory under .codex-shim/models.json")
    }
    
    func testEnsureDirectoryExists() {
        let manager = ModelsJsonManager.shared
        XCTAssertNoThrow(try manager.ensureDirectoryExists())
        let dir = manager.modelsJsonURL.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path), "Target directory should exist on disk")
    }
    
    func testProviderGroupsEmptyCheck() {
        let groups = ModelsJsonManager.shared.providerGroups()
        XCTAssertNotNil(groups, "Provider groups should never be nil")
    }
}
