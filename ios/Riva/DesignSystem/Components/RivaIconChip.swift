import SwiftUI

/// Small rounded-square icon chip used in card headers
/// (e.g. the chart icon next to "Weight tracking").
struct TPCIconChip: View {
    let systemImage: String
    var tint: Color = TPCColor.brand
    var background: Color = TPCColor.brandSoft
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
            )
    }
}

typealias RivaIconChip = TPCIconChip

#Preview {
    HStack {
        TPCIconChip(systemImage: "chart.xyaxis.line")
        TPCIconChip(systemImage: "syringe")
        TPCIconChip(systemImage: "sparkles", tint: TPCColor.accentGold, background: TPCColor.brandWash)
    }
    .padding()
    .background(TPCColor.background)
}
