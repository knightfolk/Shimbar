import XCTest
@testable import Shimbar

final class ShimStatusTests: XCTestCase {

    func testIsRunning() {
        XCTAssertTrue(ShimStatus.running.isRunning)
        XCTAssertFalse(ShimStatus.stopped.isRunning)
        XCTAssertFalse(ShimStatus.error("fail").isRunning)
        XCTAssertFalse(ShimStatus.unknown.isRunning)
    }

    func testDisplayText() {
        XCTAssertEqual(ShimStatus.running.displayText, "Running")
        XCTAssertEqual(ShimStatus.stopped.displayText, "Stopped")
        XCTAssertEqual(ShimStatus.error("network timeout").displayText, "Error: network timeout")
        XCTAssertEqual(ShimStatus.unknown.displayText, "Unknown")
    }

    func testIconNames() {
        XCTAssertEqual(ShimStatus.running.iconName, "checkmark.circle.fill")
        XCTAssertEqual(ShimStatus.stopped.iconName, "stop.circle")
        XCTAssertEqual(ShimStatus.error("x").iconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(ShimStatus.unknown.iconName, "questionmark.circle")
    }

    func testEquatable() {
        XCTAssertEqual(ShimStatus.running, ShimStatus.running)
        XCTAssertEqual(ShimStatus.stopped, ShimStatus.stopped)
        XCTAssertEqual(ShimStatus.unknown, ShimStatus.unknown)
        XCTAssertEqual(ShimStatus.error("msg"), ShimStatus.error("msg"))
        XCTAssertNotEqual(ShimStatus.error("a"), ShimStatus.error("b"))
        XCTAssertNotEqual(ShimStatus.running, ShimStatus.stopped)
    }
}
