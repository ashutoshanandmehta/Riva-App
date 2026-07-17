import SwiftUI

/// "Daily Nutrients" section — one ring tile per nutrient goal.
struct DailyNutrientsSection: View {
    let nutrients: [NutrientProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            Text("Daily Nutrients")
                .font(RivaFont.sectionTitle)
                .foregroundStyle(RivaColor.textPrimary)

            HStack(spacing: RivaSpacing.md) {
                ForEach(nutrients) { nutrient in
                    tile(nutrient)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ nutrient: NutrientProgress) -> some View {
        RivaCard {
            VStack(spacing: RivaSpacing.sm) {
                Text(nutrient.title)
                    .rivaOverline()

                RivaProgressRing(progress: nutrient.progress, size: 72, lineWidth: 7) {
                    Text(nutrient.valueText)
                        .font(RivaFont.metricM)
                        .foregroundStyle(RivaColor.textPrimary)
                }

                Text(nutrient.targetText)
                    .font(.system(size: 12))
                    .foregroundStyle(RivaColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(nutrient.title): \(nutrient.valueText) \(nutrient.targetText)")
    }
}

#Preview {
    DailyNutrientsSection(nutrients: MockHomeRepository.snapshot().nutrients)
        .padding()
        .background(RivaColor.background)
}
