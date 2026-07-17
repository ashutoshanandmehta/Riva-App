import SwiftUI

/// Current weight with the weekly delta chip and a 7-day bar strip that
/// darkens toward today.
struct CurrentWeightCard: View {
    let trend: WeightTrend
    /// Tapping the disclosure opens weight details (placeholder for now).
    let onDetails: () -> Void

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                HStack {
                    Text("Current weight")
                        .rivaOverline()
                    Spacer()
                    Button(action: onDetails) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RivaColor.textTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Weight details")
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(RivaFormat.weight(trend.currentLbs))
                        .font(RivaFont.metricXL)
                        .foregroundStyle(RivaColor.brand)
                    Text("lbs")
                        .font(RivaFont.metricUnit)
                        .foregroundStyle(RivaColor.textSecondary)
                }

                weeklyChip

                WeightBarsStrip(dailyLbs: trend.recentDailyLbs)
                    .padding(.top, RivaSpacing.xxs)
            }
        }
    }

    // MARK: Weekly delta chip

    private var weeklyChip: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.weeklyChangeLbs <= 0 ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
            Text("\(RivaFormat.signedDelta(trend.weeklyChangeLbs)) lbs this week")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(RivaColor.brand)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(RivaColor.brandWash, in: Capsule())
    }

}

#Preview {
    CurrentWeightCard(trend: MockTrackerRepository.dashboard().weight) {}
        .padding()
        .background(RivaColor.background)
}
