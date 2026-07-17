import SwiftUI

/// Tinted "Daily Targets" card — calorie and protein targets with today's
/// progress.
struct DailyTargetsCard: View {
    let calories: QuantityGoal
    let protein: QuantityGoal

    var body: some View {
        RivaCard(style: .tinted) {
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                HStack(spacing: RivaSpacing.xs) {
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RivaColor.brand)
                    Text("Daily Targets")
                        .font(RivaFont.cardTitle)
                        .foregroundStyle(RivaColor.textPrimary)
                }

                targetRow(
                    label: "Calories",
                    chip: "\(RivaFormat.wholeNumber(calories.goal)) kcal",
                    progress: calories.progress,
                    tint: RivaColor.brand
                )

                targetRow(
                    label: "Protein",
                    chip: "\(RivaFormat.grams(protein.goal))g",
                    progress: protein.progress,
                    tint: RivaColor.brand.opacity(0.55)
                )
            }
        }
    }

    private func targetRow(label: String, chip: String, progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            HStack {
                Text(label)
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
                Spacer()
                Text(chip)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RivaColor.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(RivaColor.surface, in: Capsule())
            }
            RivaProgressBar(progress: progress, height: 6, tint: tint, track: RivaColor.surface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) target: \(chip)")
    }
}

#Preview {
    let profile = MockProfileRepository.snapshot()
    return DailyTargetsCard(calories: profile.calories, protein: profile.protein)
        .padding()
        .background(RivaColor.background)
}
