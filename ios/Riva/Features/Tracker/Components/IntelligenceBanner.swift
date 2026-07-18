import SwiftUI

/// Tinted "Riva Intelligence" coaching banner at the top of Wellness.
/// The insight message supports Markdown emphasis (e.g. **injection day**),
/// with strongly-emphasized runs re-tinted in the brand color.
struct IntelligenceBanner: View {
    let insight: RivaInsight

    var body: some View {
        RivaCard(style: .tinted) {
            HStack(alignment: .top, spacing: RivaSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RivaColor.brand)
                    .frame(width: 34, height: 34)
                    .background(
                        RivaColor.surface,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                    Text("Riva Intelligence")
                        .rivaOverline(RivaColor.brand)
                    Text(AttributedString.rivaHighlighted(markdown: insight.message))
                        .font(RivaFont.body)
                        .foregroundStyle(RivaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    IntelligenceBanner(insight: MockTrackerRepository.dashboard().intelligence)
        .padding()
        .background(RivaColor.background)
}
