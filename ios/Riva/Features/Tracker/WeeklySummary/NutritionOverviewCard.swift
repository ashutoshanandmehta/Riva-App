import SwiftUI

/// "Nutrition Overview" — calories and protein vs their daily goals.
struct NutritionOverviewCard: View {
    let calories: QuantityGoal
    let protein: QuantityGoal

    var body: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            Text("Nutrition Overview")
                .font(RivaFont.sectionTitle)
                .foregroundStyle(RivaColor.textPrimary)

            RivaCard {
                VStack(spacing: RivaSpacing.md) {
                    goalRow(
                        title: "Daily Calories",
                        value: RivaFormat.wholeNumber(calories.value),
                        goal: "/ \(RivaFormat.wholeNumber(calories.goal)) kcal",
                        progress: calories.progress,
                        tint: RivaColor.brand
                    )
                    goalRow(
                        title: "Protein Goal",
                        value: "\(RivaFormat.grams(protein.value))g",
                        goal: "/ \(RivaFormat.grams(protein.goal))g",
                        progress: protein.progress,
                        // Near-ceiling macro highlighted like the wireframe.
                        tint: RivaColor.warning
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func goalRow(
        title: String,
        value: String,
        goal: String,
        progress: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RivaColor.textPrimary)
                Text(goal)
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
            RivaProgressBar(progress: progress, height: 7, tint: tint, track: tint.opacity(0.18))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(goal)")
    }
}

#Preview {
    let summary = MockTrackerRepository.summary()
    return NutritionOverviewCard(calories: summary.calories, protein: summary.protein)
        .padding()
        .background(RivaColor.background)
}
