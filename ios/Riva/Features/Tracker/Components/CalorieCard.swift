import SwiftUI

/// Calorie goal tile — kcal vs goal with a progress bar and a quick-add
/// button.
struct CalorieCard: View {
    let calorie: CalorieStatus
    /// Opens the calorie history sheet.
    let onOpen: () -> Void
    let onAdd: () -> Void

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                HStack {
                    Text("Calories")
                        .rivaOverline()
                    Spacer()
                    HistoryChevronButton(accessibilityLabel: "Calorie history", action: onOpen)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(calorie.calories)")
                        .font(TPCFont.metricM)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text("/ \(calorie.goalCalories) kcal")
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                }

                Spacer()

                HStack(alignment: .center, spacing: TPCSpacing.sm) {
                    VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                        RivaProgressBar(progress: calorie.progress, height: 7)
                        Text("\(calorie.caloriesRemaining) kcal remaining")
                            .font(.system(size: 12))
                            .foregroundStyle(TPCColor.textSecondary)
                    }

                    RivaQuickAddButton(accessibilityLabel: "Add calories", action: onAdd)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Calories: \(calorie.calories) of \(calorie.goalCalories) kcal, \(calorie.caloriesRemaining) kcal remaining"
        )
    }
}

#Preview {
    CalorieCard(calorie: MockTrackerRepository.dashboard().calorie, onOpen: {}, onAdd: {})
        .frame(width: 170, height: 155)
        .padding()
        .background(TPCColor.background)
}
