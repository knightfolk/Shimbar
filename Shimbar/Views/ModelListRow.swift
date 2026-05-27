import SwiftUI

// MARK: - ModelListRow

/// A single row representing a model in the menu bar popover's model list.
///
/// Shows a selection indicator, display name, provider badge, and an
/// optional lightning-bolt icon for passthrough models.
struct ModelListRow: View {

    let model: ShimModel
    let isActive: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Selection indicator
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                // Display name
                Text(model.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("Model ID: \(model.model)\nProvider: \(model.provider)\nBase URL: \(model.baseUrl)")

                Spacer()

                // Passthrough indicator
                if model.isPassthrough {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .help("Passthrough model")
                }

                // Provider badge
                Text(model.provider)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : .clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
