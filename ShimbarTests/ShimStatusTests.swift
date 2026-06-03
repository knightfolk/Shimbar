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

    // MARK: - HealthResponse

    func testHealthResponseDecodeFromJSON() throws {
        let json = """
        {
            "ok": true,
            "models": 5,
            "chatgpt_passthrough": true,
            "cursor_passthrough": false,
            "auto_router": true
        }
        """
        let data = json.data(using: .utf8)!
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)

        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.models, 5)
        XCTAssertTrue(health.chatgptPassthrough)
        XCTAssertFalse(health.cursorPassthrough)
        XCTAssertTrue(health.autoRouter)
    }

    func testHealthResponseDecodeAllOff() throws {
        let json = """
        {
            "ok": false,
            "models": 0,
            "chatgpt_passthrough": false,
            "cursor_passthrough": false,
            "auto_router": false
        }
        """
        let data = json.data(using: .utf8)!
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)

        XCTAssertFalse(health.ok)
        XCTAssertEqual(health.models, 0)
        XCTAssertFalse(health.chatgptPassthrough)
        XCTAssertFalse(health.cursorPassthrough)
        XCTAssertFalse(health.autoRouter)
    }

    func testHealthResponseMissingFieldsFails() {
        let json = """
        { "ok": true }
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(HealthResponse.self, from: data))
    }

    func testHealthResponseMissingOptionalFieldsDefaultsFalse() throws {
        let json = """
        {
            "ok": true,
            "models": 5,
            "chatgpt_passthrough": true
        }
        """
        let data = json.data(using: .utf8)!
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)

        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.models, 5)
        XCTAssertTrue(health.chatgptPassthrough)
        XCTAssertFalse(health.cursorPassthrough, "Missing cursor_passthrough should default to false")
        XCTAssertFalse(health.autoRouter, "Missing auto_router should default to false")
    }

    // MARK: - LiveModel

    func testLiveModelDecodeFromJSON() throws {
        let json = """
        {
            "id": "gpt-5.5",
            "object": "model",
            "created": 1700000000,
            "owned_by": "chatgpt"
        }
        """
        let data = json.data(using: .utf8)!
        let model = try JSONDecoder().decode(LiveModel.self, from: data)

        XCTAssertEqual(model.id, "gpt-5.5")
        XCTAssertEqual(model.object, "model")
        XCTAssertEqual(model.created, 1700000000)
        XCTAssertEqual(model.ownedBy, "chatgpt")
    }

    func testLiveModelIsChatGPTPassthrough() throws {
        let model = LiveModel(id: "gpt-5.5", object: "model", created: 0, ownedBy: "chatgpt")
        XCTAssertTrue(model.isChatGPTPassthrough)
        XCTAssertFalse(model.isCursorPassthrough)
        XCTAssertFalse(model.isRouter)
        XCTAssertFalse(model.isBYOK)
    }

    func testLiveModelIsCursorPassthrough() throws {
        let model = LiveModel(id: "composer-2-5", object: "model", created: 0, ownedBy: "cursor")
        XCTAssertTrue(model.isCursorPassthrough)
        XCTAssertFalse(model.isChatGPTPassthrough)
        XCTAssertFalse(model.isRouter)
        XCTAssertFalse(model.isBYOK)
    }

    func testLiveModelIsRouter() throws {
        let model = LiveModel(id: "codex-auto", object: "model", created: 0, ownedBy: "codex-shim-auto")
        XCTAssertTrue(model.isRouter)
        XCTAssertFalse(model.isChatGPTPassthrough)
        XCTAssertFalse(model.isCursorPassthrough)
        XCTAssertFalse(model.isBYOK)
    }

    func testLiveModelIsBYOK() throws {
        let model = LiveModel(id: "my-custom", object: "model", created: 0, ownedBy: "codex-shim")
        XCTAssertTrue(model.isBYOK)
        XCTAssertFalse(model.isChatGPTPassthrough)
        XCTAssertFalse(model.isCursorPassthrough)
        XCTAssertFalse(model.isRouter)
    }

    func testLiveModelHashable() {
        let a = LiveModel(id: "x", object: "model", created: 1, ownedBy: "codex-shim")
        let b = LiveModel(id: "x", object: "model", created: 1, ownedBy: "codex-shim")
        let c = LiveModel(id: "y", object: "model", created: 1, ownedBy: "codex-shim")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func testLiveModelsResponseDecode() throws {
        let json = """
        {
            "object": "list",
            "data": [
                {"id": "gpt-5.5", "object": "model", "created": 100, "owned_by": "chatgpt"},
                {"id": "claude", "object": "model", "created": 200, "owned_by": "codex-shim"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let resp = try JSONDecoder().decode(LiveModelsResponse.self, from: data)
        XCTAssertEqual(resp.object, "list")
        XCTAssertEqual(resp.data.count, 2)
        XCTAssertEqual(resp.data[0].id, "gpt-5.5")
        XCTAssertEqual(resp.data[1].id, "claude")
    }
}
