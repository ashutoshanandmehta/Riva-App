import SwiftUI

/// The dark-green Wellness hero: Today chip, streak, minutes practiced
/// against the daily goal, a cream "Start session" pill, and a thin
/// progress bar along the bottom.
struct WellnessHeroCard: View {
    let summary: WellnessSummary
    let onStart: () -> Void
    /// Nil when the backend lacks wellness support: the goal numeral is then
    /// shown but not tappable, so we never present an editor that can't save.
    let onEditGoal: (() -> Void)?

    var body: some View {
        TPCShadow.card(
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                HStack {
                    RivaBadge(text: "Today", style: .onInverse)
                    Spacer()
                    streak
                }

                HStack(alignment: .bottom, spacing: TPCSpacing.md) {
                    minutes
                    Spacer()
                    startButton
                }

                RivaProgressBar(
                    progress: progress,
                    height: 6,
                    tint: TPCColor.brandOnInverse,
                    track: TPCColor.fillOnInverse
                )
            }
            .padding(TPCSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                TPCColor.heroCard,
                in: RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous)
            )
            .rivaSurfaceOutline(cornerRadius: TPCRadius.card)
        )
    }

    private var progress: Double {
        guard summary.goalMinutes > 0 else { return 0 }
        return Double(summary.minutesToday) / Double(summary.goalMinutes)
    }

    private var streak: some View {
        HStack(spacing: TPCSpacing.xxs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TPCColor.brandOnInverse)
            Text("\(summary.streakDays)-day streak")
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.textOnInversePrimary)
        }
    }

    private var minutes: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
            Text("Minutes practiced")
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textOnInverseSecondary)
            // The goal numeral opens the goal editor when editing is supported.
            if let onEditGoal {
                Button(action: onEditGoal) {
                    minutesValue
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(summary.minutesToday) of \(summary.goalMinutes) minutes. Edit goal."
                )
            } else {
                minutesValue
                    .accessibilityLabel(
                        "\(summary.minutesToday) of \(summary.goalMinutes) minutes."
                    )
            }
        }
    }

    private var minutesValue: some View {
        HStack(alignment: .lastTextBaseline, spacing: TPCSpacing.xxs) {
            Text("\(summary.minutesToday)")
                .font(TPCFont.metricXL)
                .foregroundStyle(TPCColor.textOnInversePrimary)
            Text("/ \(summary.goalMinutes)")
                .font(TPCFont.metricM)
                .foregroundStyle(TPCColor.textOnInverseSecondary)
        }
    }

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: TPCSpacing.xxs) {
                Text("Start session")
                    .font(TPCFont.captionEmphasized)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(TPCColor.textOnHeroFill)
            .padding(.horizontal, TPCSpacing.md)
            .padding(.vertical, 10)
            .background(TPCColor.fillOnHero, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WellnessHeroCard(
        summary: WellnessSummary(minutesToday: 24, goalMinutes: 45, streakDays: 5),
        onStart: {},
        onEditGoal: {}
    )
    .padding()
    .background(TPCColor.background)
}
