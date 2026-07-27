import SwiftUI

/// Tinted "Daily Targets" card showing the account's nutrition goals.
struct DailyTargetsCard: View {
    let goals: NutritionGoals

    var body: some View {
        RivaCard(style: .tinted) {
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                HStack(spacing: TPCSpacing.xs) {
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TPCColor.brand)
                    Text("Daily Targets")
                        .font(TPCFont.cardTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                }

                targetRow(label: "Protein", chip: "\(goals.proteinGoal)g")
                targetRow(label: "Water", chip: "\(goals.waterGoal) oz")
            }
        }
    }

    private func targetRow(label: String, chip: String) -> some View {
        HStack {
            Text(label)
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textPrimary)
            Spacer()
            Text(chip)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TPCColor.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(TPCColor.surface, in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) target: \(chip)")
    }
}

#Preview {
    DailyTargetsCard(goals: MockAccountRepository.sampleBundle.nutritionGoals)
        .padding()
        .background(TPCColor.background)
}
