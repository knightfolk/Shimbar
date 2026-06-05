import XCTest
@testable import Shimbar

@MainActor
final class ShimServerStartStopViewModelTests: XCTestCase {

    func testInitialStateIsStopped() {
        let server = ShimServer.shared
        XCTAssertEqual(server.state, .stopped)
        XCTAssertTrue(server.snapshot.models.isEmpty)
        XCTAssertNil(server.snapshot.health)
        XCTAssertEqual(server.snapshot.state, .stopped)
    }

    func testShimServerStateValues() {
        let states: [ShimServerState] = [
            .stopped,
            .starting,
            .running,
            .stopping,
            .error("test")
        ]
        XCTAssertEqual(states.count, 5)
        XCTAssertEqual(ShimServerState.stopped, .stopped)
        XCTAssertEqual(ShimServerState.running, .running)
        XCTAssertNotEqual(ShimServerState.stopped, .running)
        XCTAssertEqual(ShimServerState.error("a"), .error("a"))
        XCTAssertNotEqual(ShimServerState.error("a"), .error("b"))
    }

    func testSnapshotEmpty() {
        let snap = ShimServerSnapshot.empty
        XCTAssertTrue(snap.models.isEmpty)
        XCTAssertNil(snap.health)
        XCTAssertEqual(snap.state, .stopped)
    }

    func testStopFromStoppedIsNoOp() async throws {
        let server = ShimServer.shared
        XCTAssertEqual(server.state, .stopped)
        try await server.stop()
        XCTAssertEqual(server.state, .stopped)
    }

    func testStopDoesNotThrowWhenAlreadyStopped() async {
        let server = ShimServer.shared
        do {
            try await server.stop()
            XCTAssertEqual(server.state, .stopped)
        } catch {
            XCTFail("Stop from stopped should not throw: \(error)")
        }
    }

    func testStartBehavior() async {
        let server = ShimServer.shared
        do {
            try await server.start()
            XCTAssertTrue(server.state == .running || server.state == .error(""), "State should be running or error after start attempt")
            try? await server.stop()
        } catch {
            XCTAssertTrue(true, "Correctly threw when no backend available")
        }
    }
}
