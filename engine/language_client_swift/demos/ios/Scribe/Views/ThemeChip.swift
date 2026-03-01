import SwiftUI

/// Small pill tag showing a single theme label.
struct ThemeChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .cornerRadius(20)
    }
}
