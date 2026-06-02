import XCTest
@testable import Shimbar

final class AppSettingsTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.shimbar.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultValues() {
        let settings = AppSettings(defaults: testDefaults)

        XCTAssertEqual(settings.shimPath, "codex-shim")
        XCTAssertEqual(settings.port, 8765)
        XCTAssertEqual(settings.pollingInterval, 5.0)
        XCTAssertFalse(settings.disableChatGPTPassthrough)
        XCTAssertNil(settings.lastActiveModel)
        XCTAssertFalse(settings.collapseModelSection)
    }

    func testShimPathPersistence() {
        let settings = AppSettings(defaults: testDefaults)
        settings.shimPath = "/usr/local/bin/codex-shim"
        XCTAssertEqual(settings.shimPath, "/usr/local/bin/codex-shim")

        let reloaded = AppSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.shimPath, "/usr/local/bin/codex-shim")
    }

    func testPortPersistence() {
        let settings = AppSettings(defaults: testDefaults)
        settings.port = 9000
        XCTAssertEqual(settings.port, 9000)

        let reloaded = AppSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.port, 9000)
    }

    func testPollingIntervalPersistence() {
        let settings = AppSettings(defaults: testDefaults)
        settings.pollingInterval = 10.0
        XCTAssertEqual(settings.pollingInterval, 10.0)

        let reloaded = AppSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.pollingInterval, 10.0)
    }

    func testDisableChatGPTPassthroughPersistence() {
        let settings = AppSettings(defaults: testDefaults)
        settings.disableChatGPTPassthrough = true
        XCTAssertTrue(settings.disableChatGPTPassthrough)

        let reloaded = AppSettings(defaults: testDefaults)
        XCTAssertTrue(reloaded.disableChatGPTPassthrough)
    }

    func testLastActiveModelPersistence() {
        let settings = AppSettings(defaults: testDefaults)
        settings.lastActiveModel = "gpt-4o"
        XCTAssertEqual(settings.lastActiveModel, "gpt-4o")

        let reloaded = AppSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.lastActiveModel, "gpt-4o")
    }

    func testCollapseModelSectionPersistence() {
        let settings = AppSettings(defaults: testDefaults)
        settings.collapseModelSection = true
        XCTAssertTrue(settings.collapseModelSection)

        let reloaded = AppSettings(defaults: testDefaults)
        XCTAssertTrue(reloaded.collapseModelSection)
    }

    func testMultipleSettingsChangesPersist() {
        let settings = AppSettings(defaults: testDefaults)
        settings.shimPath = "/opt/homebrew/bin/codex-shim"
        settings.port = 9999
        settings.pollingInterval = 15.0
        settings.disableChatGPTPassthrough = true
        settings.lastActiveModel = "claude-sonnet-4"
        settings.collapseModelSection = true

        let reloaded = AppSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.shimPath, "/opt/homebrew/bin/codex-shim")
        XCTAssertEqual(reloaded.port, 9999)
        XCTAssertEqual(reloaded.pollingInterval, 15.0)
        XCTAssertTrue(reloaded.disableChatGPTPassthrough)
        XCTAssertEqual(reloaded.lastActiveModel, "claude-sonnet-4")
        XCTAssertTrue(reloaded.collapseModelSection)
    }
}
