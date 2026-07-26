import SwiftUI

/// Titration status card: level badge, current-dose ring, and the next-dose
/// schedule tile with a live countdown.
struct CurrentDoseCard: View {
    let titration: DoseTitration
    let nextDose: ScheduledShot

    var body: some View {
        RivaCard {
            VStack(spacing: TPCSpacing.lg) {
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
            VStack(spacing: TPCSpacing.xxs) {
                Text("Current dose")
                    .rivaOverline()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(RivaFormat.doseNumber(titration.currentDoseMg))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(TPCColor.textPrimary)
                    Text("mg")
                        .font(TPCFont.metricUnit)
                        .foregroundStyle(TPCColor.textSecondary)
                }
                Text("\(titration.weeksCompleted)/\(titration.weeksPerLevel) weeks")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
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
                    .foregroundStyle(TPCColor.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(RivaFormat.hoursRemaining(until: nextDose.date))
                    .font(TPCFont.metricM)
                    .foregroundStyle(TPCColor.brand)
                Text("Remaining")
                    .rivaOverline()
            }
        }
        .padding(TPCSpacing.sm)
        .background(
            TPCColor.brandWash,
            in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
        )
    }
}

#Preview {
    let dashboard = MockMedicationRepository.dashboard()
    return CurrentDoseCard(titration: dashboard.titration, nextDose: dashboard.nextDose)
        .padding()
        .background(TPCColor.background)
}
