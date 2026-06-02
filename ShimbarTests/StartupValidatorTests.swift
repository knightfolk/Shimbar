import XCTest
@testable import Shimbar

@MainActor
final class StartupValidatorTests: XCTestCase {

    func testCheckItemInitialization() {
        let item = StartupValidator.CheckItem(
            id: "test",
            title: "Test Check",
            description: "A test check",
            status: .checking,
            isCritical: true
        )

        XCTAssertEqual(item.id, "test")
        XCTAssertEqual(item.title, "Test Check")
        XCTAssertTrue(item.isCritical)
    }

    func testCheckStatusSuccess() {
        let status = StartupValidator.CheckStatus.success
        XCTAssertTrue(status.isSuccess)
        XCTAssertFalse(status.isFailure)
        XCTAssertFalse(status.isWarning)
    }

    func testCheckStatusFailure() {
        let status = StartupValidator.CheckStatus.failure("Something broke")
        XCTAssertFalse(status.isSuccess)
        XCTAssertTrue(status.isFailure)
        XCTAssertFalse(status.isWarning)
    }

    func testCheckStatusWarning() {
        let status = StartupValidator.CheckStatus.warning("Heads up")
        XCTAssertFalse(status.isSuccess)
        XCTAssertFalse(status.isFailure)
        XCTAssertTrue(status.isWarning)
    }

    func testCheckStatusChecking() {
        let status = StartupValidator.CheckStatus.checking
        XCTAssertFalse(status.isSuccess)
        XCTAssertFalse(status.isFailure)
        XCTAssertFalse(status.isWarning)
    }

    func testDefaultItemsCount() {
        let validator = StartupValidator()
        XCTAssertTrue(validator.items.count >= 6, "Should have at least the 6 standard check items")
    }

    func testDefaultCriticalItems() {
        let validator = StartupValidator()
        let criticalIds = validator.items.filter(\.isCritical).map(\.id)
        XCTAssertTrue(criticalIds.contains("binary"), "Binary check should be critical")
        XCTAssertTrue(criticalIds.contains("models"), "Models check should be critical")
    }

    func testDefaultOptionalItems() {
        let validator = StartupValidator()
        let optionalIds = validator.items.filter { !$0.isCritical }.map(\.id)
        XCTAssertTrue(optionalIds.contains("codexApp"), "Codex app should be optional by default")
        XCTAssertTrue(optionalIds.contains("npx"), "npx should be optional by default")
    }

    func testResetItemsClearsStatuses() {
        let validator = StartupValidator()
        for i in validator.items.indices {
            validator.items[i].status = .success
        }
        validator.resetItems()
        for item in validator.items {
            XCTAssertEqual(item.status, .checking, "Item \(item.id) should be reset to checking")
        }
    }

    func testHasCriticalFailuresWhenNoneFailed() {
        let validator = StartupValidator()
        XCTAssertFalse(validator.hasCriticalFailures)
    }

    func testIsFullyReadyAfterResetWithoutFailures() {
        let validator = StartupValidator()
        XCTAssertTrue(validator.isFullyReady, "After reset with no failures and isChecking=false, should be ready")
    }

    func testIsNotFullyReadyWhileChecking() {
        let validator = StartupValidator()
        validator.isChecking = true
        XCTAssertFalse(validator.isFullyReady)
    }
}
