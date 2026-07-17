import SwiftUI

/// AI coaching insight card.
struct RivaInsightCard: View {
    let insight: RivaInsight

    var body: some View {
        RivaCard {
            HStack(alignment: .top, spacing: RivaSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RivaColor.brand)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                    Text("Riva Insight")
                        .rivaOverline(RivaColor.brand)
                    Text(insight.message)
                        .font(RivaFont.body)
                        .foregroundStyle(RivaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    RivaInsightCard(insight: MockHomeRepository.snapshot().insight)
        .padding()
        .background(RivaColor.background)
}
