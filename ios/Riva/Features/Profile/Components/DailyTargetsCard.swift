import SwiftUI

/// Tinted "Daily Targets" card showing the account's nutrition goals.
struct DailyTargetsCard: View {
    let goals: NutritionGoals

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

                targetRow(label: "Protein", chip: "\(goals.proteinGoal)g")
                targetRow(label: "Carbs", chip: "\(goals.carbGoal)g")
                targetRow(label: "Fiber", chip: "\(goals.fiberGoal)g")
                targetRow(label: "Water", chip: "\(goals.waterGoal) oz")
            }
        }
    }

    private func targetRow(label: String, chip: String) -> some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) target: \(chip)")
    }
}

#Preview {
    DailyTargetsCard(goals: MockAccountRepository.sampleBundle.nutritionGoals)
        .padding()
        .background(RivaColor.background)
}
