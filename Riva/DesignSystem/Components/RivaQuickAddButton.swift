import SwiftUI

/// Floating circular "+" button used on dashboard tiles for one-tap logging
/// (water, protein, side effects, sleep).
struct RivaQuickAddButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RivaColor.textOnBrand)
                .frame(width: 36, height: 36)
                .background(RivaColor.brand, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    RivaQuickAddButton(accessibilityLabel: "Add") {}
        .padding()
        .background(RivaColor.background)
}
