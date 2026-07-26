import SwiftUI

/// High-contrast "Next Shot" card: drug, dose, countdown ring, and schedule.
struct NextShotCard: View {
    let shot: ScheduledShot
    /// Tapping the schedule row opens dose details (placeholder for now).
    let onDetails: () -> Void

    var body: some View {
        RivaCard(style: .inverse) {
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                        Text("Next shot")
                            .rivaOverline(TPCColor.textOnInverseSecondary)
                        Text(shot.drugName)
                            .font(TPCFont.cardHero)
                            .foregroundStyle(TPCColor.textOnInversePrimary)
                        RivaBadge(text: RivaFormat.doseMg(shot.doseMg), style: .onInverse)
                    }

                    Spacer()

                    RivaProgressRing(
                        progress: shot.cycleProgress(),
                        size: 64,
                        lineWidth: 5.5,
                        tint: TPCColor.brandOnInverse,
                        track: TPCColor.fillOnInverse
                    ) {
                        VStack(spacing: -1) {
                            Text("\(shot.daysRemaining())d")
                                .font(TPCFont.metricM)
                                .foregroundStyle(TPCColor.textOnInversePrimary)
                            Text("left")
                                .font(.system(size: 10))
                                .foregroundStyle(TPCColor.textOnInverseSecondary)
                        }
                    }
                    .accessibilityLabel("\(shot.daysRemaining()) days until your next shot")
                }

                Button(action: onDetails) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(RivaFormat.shotDate(shot.date))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TPCColor.textOnInversePrimary)
                            Text("Suggested site - \(shot.suggestedSite)")
                                .font(.system(size: 12))
                                .foregroundStyle(TPCColor.textOnInverseSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TPCColor.textOnInverseSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shot details")
            }
        }
    }
}

#Preview {
    NextShotCard(shot: MockHomeRepository.snapshot().nextShot) {}
        .padding()
        .background(TPCColor.background)
}
