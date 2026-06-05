import SwiftUI

struct NativeServerBadge: View {
    let useNativeServer: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(useNativeServer ? Color.green : Color.yellow)
                .frame(width: 8, height: 8)
            Text(useNativeServer ? "Native" : "Python")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(useNativeServer ? .green : .orange)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill((useNativeServer ? Color.green : Color.orange).opacity(0.12))
        )
    }
}

#Preview("Native") {
    NativeServerBadge(useNativeServer: true)
        .padding()
}

#Preview("Python") {
    NativeServerBadge(useNativeServer: false)
        .padding()
}
