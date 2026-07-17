import SwiftUI

/// Centered stat tile on the summary screen (hydration, sleep average).
struct SummaryStatTile: View {
    let systemImage: String
    let caption: String
    let value: String

    var body: some View {
        RivaCard {
            VStack(spacing: RivaSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(RivaColor.brand)
                Text(caption)
                    .rivaOverline()
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(RivaColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption): \(value)")
    }
}

#Preview {
    HStack(spacing: RivaSpacing.md) {
        SummaryStatTile(systemImage: "drop", caption: "Hydration", value: "2.4L / day")
        SummaryStatTile(systemImage: "moon", caption: "Sleep avg", value: "7h 42m")
    }
    .padding()
    .background(RivaColor.background)
}
