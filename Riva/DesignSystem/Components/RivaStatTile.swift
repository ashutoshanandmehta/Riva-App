import SwiftUI

/// Compact tinted tile for a single stat ("THIS WEEK  ↓ -1.2 lbs").
struct RivaStatTile: View {
    let caption: String
    let systemImage: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text(caption)
                .rivaOverline()

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RivaColor.brand)
                Text(value)
                    .font(RivaFont.metricM)
                    .foregroundStyle(RivaColor.textPrimary)
                Text(unit)
                    .font(RivaFont.metricUnit)
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
        .padding(RivaSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RivaColor.brandWash,
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
        )
    }
}

#Preview {
    HStack(spacing: RivaSpacing.sm) {
        RivaStatTile(caption: "This week", systemImage: "arrow.down", value: "-1.2", unit: "lbs")
        RivaStatTile(caption: "Total loss", systemImage: "arrow.down.circle", value: "-18.4", unit: "lbs")
    }
    .padding()
    .background(RivaColor.surface)
}
