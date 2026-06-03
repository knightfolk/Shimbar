import Foundation
import SwiftUI

// MARK: - ShimStatus

/// Represents the current status of the codex-shim daemon process.
///
/// Used throughout the UI to display connection state and control
/// visual indicators (icon color, status text) in the menu bar.
enum ShimStatus: Equatable, Hashable {
    /// The shim daemon is running and responding normally.
    case running
    /// The shim daemon is not running.
    case stopped
    /// The shim daemon encountered an error.
    case error(String)
    /// The shim daemon status could not be determined.
    case unknown

    // MARK: - Computed Properties

    /// Whether the shim daemon is currently running.
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// A human-readable description of the current status.
    var displayText: String {
        switch self {
        case .running:
            return "Running"
        case .stopped:
            return "Stopped"
        case .error(let message):
            return "Error: \(message)"
        case .unknown:
            return "Unknown"
        }
    }

    /// The SF Symbol name representing the current status.
    var iconName: String {
        switch self {
        case .running:
            return "checkmark.circle.fill"
        case .stopped:
            return "stop.circle"
        case .error:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    /// The SwiftUI color associated with the current status.
    var iconColor: Color {
        switch self {
        case .running:
            return .green
        case .stopped:
            return .secondary
        case .error:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

// MARK: - HealthResponse

struct HealthResponse: Codable {
    let ok: Bool
    let models: Int
    let chatgptPassthrough: Bool
    let cursorPassthrough: Bool
    let autoRouter: Bool

    enum CodingKeys: String, CodingKey {
        case ok
        case models
        case chatgptPassthrough = "chatgpt_passthrough"
        case cursorPassthrough = "cursor_passthrough"
        case autoRouter = "auto_router"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try container.decode(Bool.self, forKey: .ok)
        self.models = try container.decode(Int.self, forKey: .models)
        self.chatgptPassthrough = try container.decodeIfPresent(Bool.self, forKey: .chatgptPassthrough) ?? false
        self.cursorPassthrough = try container.decodeIfPresent(Bool.self, forKey: .cursorPassthrough) ?? false
        self.autoRouter = try container.decodeIfPresent(Bool.self, forKey: .autoRouter) ?? false
    }
}

// MARK: - LiveModel

struct LiveModel: Identifiable, Codable, Hashable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }

    var isChatGPTPassthrough: Bool { ownedBy == "chatgpt" }
    var isCursorPassthrough: Bool { ownedBy == "cursor" }
    var isRouter: Bool { ownedBy == "codex-shim-auto" }
    var isBYOK: Bool { ownedBy == "codex-shim" }
}

struct LiveModelsResponse: Codable {
    let object: String
    let data: [LiveModel]
}
