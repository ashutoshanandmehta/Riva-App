import SwiftUI

/// "Calories today" card — conic ring showing calories remaining, macro bars
/// for nutrients from the snapshot, and a quick "+ Log food" button.
struct CaloriesTodayCard: View {
    let nutrients: [NutrientProgress]
    let onLogFood: () -> Void

    private var calories: NutrientProgress? { nutrients.first { $0.title == "Calories" } }
    private var others: [NutrientProgress] { nutrients.filter { $0.title != "Calories" } }

    var body: some View {
        TPCCard {
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                HStack {
                    Text("Calories today")
                        .font(TPCFont.sectionTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Spacer()
                    Button(action: onLogFood) {
                        Text("+ Log food")
                            .font(TPCFont.captionEmphasized)
                            .foregroundStyle(TPCColor.textOnInversePrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(TPCColor.surfaceInverse, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if let cal = calories {
                    HStack(alignment: .center, spacing: TPCSpacing.lg) {
                        calorieRing(cal)
                        macroStack(cal)
                    }
                }
            }
        }
    }

    private func calorieRing(_ cal: NutrientProgress) -> some View {
        TPCProgressRing(
            progress: cal.progress,
            size: 92,
            lineWidth: 10,
            tint: TPCColor.brand,
            track: TPCColor.fillNeutral
        ) {
            VStack(spacing: 1) {
                Text(remainingText(cal))
                    .font(TPCFont.metricL)
                    .foregroundStyle(TPCColor.textPrimary)
                    .minimumScaleFactor(0.7)
                Text("LEFT")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(TPCColor.textTertiary)
                    .kerning(0.8)
            }
        }
        .accessibilityLabel("Calories: \(cal.valueText) eaten, \(cal.targetText)")
    }

    private func macroStack(_ cal: NutrientProgress) -> some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(cal.valueText)
                    .font(TPCFont.metricL)
                    .foregroundStyle(TPCColor.textPrimary)
                Text(cal.targetText)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
            }

            ForEach(others) { nutrient in
                macroBar(nutrient)
            }
        }
    }

    private func macroBar(_ nutrient: NutrientProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nutrient.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TPCColor.textSecondary)
                Spacer()
                Text("\(nutrient.valueText) \(nutrient.targetText)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TPCColor.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(TPCColor.fillNeutral)
                    Capsule()
                        .fill(nutrient.title == "Protein" ? TPCColor.brandDeep : TPCColor.brand)
                        .frame(width: geo.size.width * nutrient.progress)
                }
            }
            .frame(height: 5)
        }
    }

    private func remainingText(_ cal: NutrientProgress) -> String {
        let goal = goalNumber(from: cal.targetText)
        let eaten = numberValue(from: cal.valueText)
        let left = max(0, goal - eaten)
        return left > 999 ? "\(Int(left / 1000))k" : "\(Int(left))"
    }

    private func goalNumber(from text: String) -> Double {
        text.split(whereSeparator: { !$0.isNumber }).first.flatMap { Double($0) } ?? 0
    }

    private func numberValue(from text: String) -> Double {
        text.split(whereSeparator: { !$0.isNumber }).first.flatMap { Double($0) } ?? 0
    }
}

/// Legacy name — keep compiling until all call-sites are updated.
typealias DailyNutrientsSection = CaloriesTodayCard

#Preview {
    CaloriesTodayCard(nutrients: MockHomeRepository.snapshot().nutrients) {}
        .padding()
        .background(TPCColor.background)
}
