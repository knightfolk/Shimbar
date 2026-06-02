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
