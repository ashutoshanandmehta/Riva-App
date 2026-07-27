import SwiftUI

/// "Calories today" card — a ring showing calories remaining, macro bars for
/// every other nutrient in the snapshot, and a quick "+ Log food" button.
struct CaloriesTodayCard: View {
    let nutrients: [NutrientProgress]
    let onLogFood: () -> Void

    private var calories: NutrientProgress? { nutrients.first { $0.title == "Calories" } }
    private var macros: [NutrientProgress] { nutrients.filter { $0.title != "Calories" } }

    var body: some View {
        TPCCard {
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                HStack {
                    Text("Calories today")
                        .font(TPCFont.sectionTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Spacer()
                    Button("+ Log food", action: onLogFood)
                        .buttonStyle(.tpcInverse)
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
            tint: TPCColor.brandDeep,
            track: TPCColor.fillNeutral
        ) {
            VStack(spacing: 0) {
                Text(NutrientProgress.format(cal.remaining))
                    .font(TPCFont.metricL)
                    .foregroundStyle(TPCColor.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("kcal left")
                    .font(TPCFont.caption)
                    .foregroundStyle(TPCColor.textTertiary)
            }
            .padding(.horizontal, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Calories: \(cal.valueText) eaten \(cal.targetText), "
            + "\(NutrientProgress.format(cal.remaining)) left"
        )
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

            ForEach(macros) { macro in
                macroBar(macro)
            }
        }
    }

    private func macroBar(_ macro: NutrientProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(macro.title)
                    .font(TPCFont.captionEmphasized)
                    .foregroundStyle(TPCColor.textSecondary)
                Spacer()
                Text(macro.pairText)
                    .font(TPCFont.captionEmphasized)
                    .foregroundStyle(TPCColor.textSecondary)
            }
            TPCProgressBar(
                progress: macro.progress,
                height: 6,
                tint: tint(for: macro.title),
                track: TPCColor.fillNeutral
            )
        }
        .accessibilityElement(children: .combine)
    }

    /// A nutrient the server adds later still renders — it just falls back to
    /// the brand gold rather than getting its own token.
    private func tint(for title: String) -> Color {
        switch title {
        case "Protein": TPCColor.macroProtein
        case "Carbs":   TPCColor.macroCarbs
        case "Fiber":   TPCColor.macroFiber
        default:        TPCColor.brand
        }
    }
}

/// Legacy name — keep compiling until all call-sites are updated.
typealias DailyNutrientsSection = CaloriesTodayCard

#Preview {
    CaloriesTodayCard(nutrients: MockHomeRepository.snapshot().nutrients) {}
        .padding()
        .background(TPCColor.background)
}
