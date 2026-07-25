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
        RivaShadow.card(
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                HStack {
                    RivaBadge(text: "Today", style: .onInverse)
                    Spacer()
                    streak
                }

                HStack(alignment: .bottom, spacing: RivaSpacing.md) {
                    minutes
                    Spacer()
                    startButton
                }

                RivaProgressBar(
                    progress: progress,
                    height: 6,
                    tint: RivaColor.brandOnInverse,
                    track: RivaColor.fillOnInverse
                )
            }
            .padding(RivaSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RivaColor.heroCard,
                in: RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous)
            )
            .rivaSurfaceOutline(cornerRadius: RivaRadius.card)
        )
    }

    private var progress: Double {
        guard summary.goalMinutes > 0 else { return 0 }
        return Double(summary.minutesToday) / Double(summary.goalMinutes)
    }

    private var streak: some View {
        HStack(spacing: RivaSpacing.xxs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RivaColor.brandOnInverse)
            Text("\(summary.streakDays)-day streak")
                .font(RivaFont.captionEmphasized)
                .foregroundStyle(RivaColor.textOnInversePrimary)
        }
    }

    private var minutes: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
            Text("Minutes practiced")
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textOnInverseSecondary)
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
        HStack(alignment: .lastTextBaseline, spacing: RivaSpacing.xxs) {
            Text("\(summary.minutesToday)")
                .font(RivaFont.metricXL)
                .foregroundStyle(RivaColor.textOnInversePrimary)
            Text("/ \(summary.goalMinutes)")
                .font(RivaFont.metricM)
                .foregroundStyle(RivaColor.textOnInverseSecondary)
        }
    }

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: RivaSpacing.xxs) {
                Text("Start session")
                    .font(RivaFont.captionEmphasized)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(RivaColor.textOnHeroFill)
            .padding(.horizontal, RivaSpacing.md)
            .padding(.vertical, 10)
            .background(RivaColor.fillOnHero, in: Capsule())
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
    .background(RivaColor.background)
}
