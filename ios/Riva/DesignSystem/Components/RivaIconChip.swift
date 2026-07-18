import SwiftUI

/// Small rounded-square icon chip used in card headers
/// (e.g. the chart icon next to "Weight Tracking").
struct RivaIconChip: View {
    let systemImage: String
    var tint: Color = RivaColor.brand
    var background: Color = RivaColor.brandWash
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

#Preview {
    HStack {
        RivaIconChip(systemImage: "chart.xyaxis.line")
        RivaIconChip(systemImage: "syringe")
        RivaIconChip(systemImage: "sparkles")
    }
    .padding()
}
