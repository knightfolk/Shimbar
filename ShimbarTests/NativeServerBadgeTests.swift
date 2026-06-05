import XCTest
@testable import Shimbar

final class NativeServerBadgeTests: XCTestCase {

    func testNativeServerBadgeDefaultsToFalse() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.native.badge")!)
        XCTAssertFalse(settings.useNativeServer)
    }

    func testNativeServerBadgeToggles() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.native.badge.toggle")!)
        XCTAssertFalse(settings.useNativeServer)

        settings.useNativeServer = true
        XCTAssertTrue(settings.useNativeServer)

        settings.useNativeServer = false
        XCTAssertFalse(settings.useNativeServer)
    }

    func testNativeServerBadgePersisted() {
        let suite = "test.native.badge.persist"
        let settings1 = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings1.useNativeServer = true

        let settings2 = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(settings2.useNativeServer)

        settings2.useNativeServer = false
    }

    func testBadgeIsDeterministicWhenToggled() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.badge.deterministic")!)

        settings.useNativeServer = false
        let isNativeWhenOff = settings.useNativeServer
        XCTAssertFalse(isNativeWhenOff)

        settings.useNativeServer = true
        let isNativeWhenOn = settings.useNativeServer
        XCTAssertTrue(isNativeWhenOn)
    }
}
