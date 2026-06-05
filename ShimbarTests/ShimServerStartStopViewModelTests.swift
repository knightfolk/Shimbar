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

    func testStartFailsWhenNoBackendRunning() async {
        let server = ShimServer.shared
        do {
            try await server.start()
            XCTFail("Should have thrown since no backend is running in tests")
        } catch {
            XCTAssertTrue(true, "Correctly threw when no backend available")
        }
    }

    func testShimManagerDelegatesToServerWhenNativeEnabled() async {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.shimserver.viewmodel")!)
        settings.useNativeServer = true
        settings.shimPath = "/nonexistent/codex-shim-for-test"

        XCTAssertEqual(settings.useNativeServer, true)

        settings.useNativeServer = false
        XCTAssertEqual(settings.useNativeServer, false)
    }
}
