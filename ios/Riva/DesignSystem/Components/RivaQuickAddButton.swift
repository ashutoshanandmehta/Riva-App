import SwiftUI

/// Small circular "+" button for one-tap logging on dashboard tiles
/// (water, protein, side effects, sleep).
struct TPCQuickAddButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TPCColor.textOnBrand)
                .frame(width: 34, height: 34)
                .background(TPCColor.brand, in: Circle())
                .shadow(color: TPCColor.brandDeep.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

typealias RivaQuickAddButton = TPCQuickAddButton

#Preview {
    TPCQuickAddButton(accessibilityLabel: "Add water") {}
        .padding()
        .background(TPCColor.background)
}
