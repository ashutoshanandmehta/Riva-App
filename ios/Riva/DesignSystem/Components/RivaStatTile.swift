import SwiftUI

/// Compact tinted tile for a single stat ("THIS WEEK  ↓ 2.4 lbs").
struct TPCStatTile: View {
    let caption: String
    let systemImage: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
            Text(caption)
                .tpcOverline()

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TPCColor.positive)
                Text(value)
                    .font(TPCFont.metricM)
                    .foregroundStyle(TPCColor.positive)
                Text(unit)
                    .font(TPCFont.metricUnit)
                    .foregroundStyle(TPCColor.textSecondary)
            }
        }
        .padding(TPCSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TPCColor.fillNeutral,
            in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
                .strokeBorder(TPCColor.surfaceOutline, lineWidth: 1)
        )
    }
}

typealias RivaStatTile = TPCStatTile

#Preview {
    HStack(spacing: TPCSpacing.sm) {
        TPCStatTile(caption: "This week",  systemImage: "arrow.down", value: "↓ 2.4", unit: "lbs")
        TPCStatTile(caption: "Total loss", systemImage: "arrow.down", value: "↓ 17.6", unit: "lbs")
    }
    .padding()
    .background(TPCColor.surface)
}
