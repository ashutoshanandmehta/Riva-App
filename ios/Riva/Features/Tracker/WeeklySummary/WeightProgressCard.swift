import SwiftUI

/// Week-scoped weight progress: change, daily bars, and totals.
struct WeightProgressCard: View {
    let progress: WeeklyWeightProgress

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                HStack {
                    Text("Weight progress")
                        .rivaOverline()
                    Spacer()
                    RivaBadge(text: progress.isOnTrack ? "On Track" : "Off Pace", style: .brand)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(RivaFormat.signedDelta(progress.changeLbs))
                        .font(TPCFont.metricXL)
                        .foregroundStyle(TPCColor.brand)
                    Text("lbs")
                        .font(TPCFont.metricUnit)
                        .foregroundStyle(TPCColor.textSecondary)
                }

                WeightBarsStrip(dailyLbs: progress.dailyLbs, barHeight: 48)

                HStack {
                    Text("Total lost: \(RivaFormat.weight(progress.totalLostLbs)) lbs")
                    Spacer()
                    Text("Goal: \(RivaFormat.doseNumber(progress.goalLbs)) lbs")
                }
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WeightProgressCard(progress: MockTrackerRepository.summary().weight)
        .padding()
        .background(TPCColor.background)
}
