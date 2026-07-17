import SwiftUI

/// Week-scoped weight progress: change, daily bars, and totals.
struct WeightProgressCard: View {
    let progress: WeeklyWeightProgress

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                HStack {
                    Text("Weight progress")
                        .rivaOverline()
                    Spacer()
                    RivaBadge(text: progress.isOnTrack ? "On Track" : "Off Pace", style: .brand)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(RivaFormat.signedDelta(progress.changeLbs))
                        .font(RivaFont.metricXL)
                        .foregroundStyle(RivaColor.brand)
                    Text("lbs")
                        .font(RivaFont.metricUnit)
                        .foregroundStyle(RivaColor.textSecondary)
                }

                WeightBarsStrip(dailyLbs: progress.dailyLbs, barHeight: 48)

                HStack {
                    Text("Total lost: \(RivaFormat.weight(progress.totalLostLbs)) lbs")
                    Spacer()
                    Text("Goal: \(RivaFormat.doseNumber(progress.goalLbs)) lbs")
                }
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WeightProgressCard(progress: MockTrackerRepository.summary().weight)
        .padding()
        .background(RivaColor.background)
}
