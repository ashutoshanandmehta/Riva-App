import SwiftUI

/// Titration status card: level badge, current-dose ring, and the next-dose
/// schedule tile with a live countdown.
struct CurrentDoseCard: View {
    let titration: DoseTitration
    let nextDose: ScheduledShot

    var body: some View {
        RivaCard {
            VStack(spacing: RivaSpacing.lg) {
                doseRing
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        RivaBadge(text: "Level \(titration.level)", style: .brand)
                    }

                nextDoseTile
            }
        }
    }

    // MARK: Ring

    private var doseRing: some View {
        RivaProgressRing(progress: titration.progress, size: 150, lineWidth: 11) {
            VStack(spacing: RivaSpacing.xxs) {
                Text("Current dose")
                    .rivaOverline()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(RivaFormat.doseNumber(titration.currentDoseMg))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(RivaColor.textPrimary)
                    Text("mg")
                        .font(RivaFont.metricUnit)
                        .foregroundStyle(RivaColor.textSecondary)
                }
                Text("\(titration.weeksCompleted)/\(titration.weeksPerLevel) weeks")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Current dose \(RivaFormat.doseMg(titration.currentDoseMg)), week \(titration.weeksCompleted) of \(titration.weeksPerLevel) at level \(titration.level)"
        )
    }

    // MARK: Next dose

    private var nextDoseTile: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Next dose")
                    .rivaOverline()
                Text(RivaFormat.doseSchedule(nextDose.date))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RivaColor.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(RivaFormat.hoursRemaining(until: nextDose.date))
                    .font(RivaFont.metricM)
                    .foregroundStyle(RivaColor.brand)
                Text("Remaining")
                    .rivaOverline()
            }
        }
        .padding(RivaSpacing.sm)
        .background(
            RivaColor.brandWash,
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
        )
    }
}

#Preview {
    let dashboard = MockMedicationRepository.dashboard()
    return CurrentDoseCard(titration: dashboard.titration, nextDose: dashboard.nextDose)
        .padding()
        .background(RivaColor.background)
}
