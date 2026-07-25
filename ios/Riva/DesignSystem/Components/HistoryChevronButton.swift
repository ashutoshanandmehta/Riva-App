import SwiftUI

/// Small up/down chevron disclosure used on dashboard tiles to open a
/// history sheet.
struct HistoryChevronButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RivaColor.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    HistoryChevronButton(accessibilityLabel: "History") {}
        .padding()
        .background(RivaColor.background)
}
