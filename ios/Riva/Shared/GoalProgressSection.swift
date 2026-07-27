import SwiftUI

/// Journey progress toward the target weight: current weight, target, a
/// progress bar, and the percent-complete / lbs-to-go footer.
///
/// Shared by the Tracker's Weight Tracking card and Home's Goal Progress card,
/// so the same numbers read identically in both places. Callers supply the
/// surrounding card.
struct GoalProgressSection: View {
    let goal: WeightGoalProgress

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                    Text("Goal progress")
                        .rivaOverline()
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(RivaFormat.weight(goal.currentLbs))
                            .font(TPCFont.metricXL)
                            .foregroundStyle(TPCColor.textPrimary)
                        Text("lbs")
                            .font(TPCFont.metricUnit)
                            .foregroundStyle(TPCColor.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: TPCSpacing.xxs) {
                    Text("Target")
                        .rivaOverline()
                    Text("\(RivaFormat.weight(goal.targetLbs).replacingOccurrences(of: ".0", with: "")) lbs")
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(TPCColor.brand)
                }
            }

            RivaProgressBar(progress: goal.progress)

            HStack {
                Text("\(Int((goal.progress * 100).rounded()))% complete")
                Spacer()
                Text("\(RivaFormat.weight(goal.lbsToGo)) lbs to go")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(TPCColor.textSecondary)
        }
    }
}

#Preview {
    TPCCard {
        GoalProgressSection(
            goal: WeightGoalProgress(currentLbs: 164.2, targetLbs: 145, progress: 0.65)
        )
    }
    .padding()
    .background(TPCColor.background)
}
