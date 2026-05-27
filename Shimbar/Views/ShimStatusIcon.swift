import SwiftUI

// MARK: - ShimStatusIcon

/// The menu bar icon that reflects the current status of the codex-shim daemon.
///
/// Renders as a diamond shape using SF Symbols, with visual variations
/// for running, stopped, error, and unknown states.
struct ShimStatusIcon: View {

    let status: ShimStatus

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
    }

    // MARK: - Private Helpers

    private var iconName: String {
        switch status {
        case .running:
            return "diamond.fill"
        case .stopped:
            return "diamond"
        case .error:
            return "exclamationmark.diamond.fill"
        case .unknown:
            return "diamond"
        }
    }
}

// MARK: - Preview

#Preview("Running") {
    ShimStatusIcon(status: .running)
        .padding()
}

#Preview("Stopped") {
    ShimStatusIcon(status: .stopped)
        .padding()
}

#Preview("Error") {
    ShimStatusIcon(status: .error("Something went wrong"))
        .padding()
}
