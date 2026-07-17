import SwiftUI

/// Estimated active-drug level card ("1.8 mg in system") with a level gauge.
struct MedicationLevelCard: View {
    let estimate: MedicationLevelEstimate

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                HStack(spacing: RivaSpacing.xs) {
                    RivaIconChip(systemImage: "syringe")
                    Text("Medication level")
                        .font(RivaFont.cardTitle)
                        .foregroundStyle(RivaColor.textPrimary)
                    Spacer()
                    RivaBadge(text: "Estimated")
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", estimate.currentMg))
                        .font(RivaFont.metricXL)
                        .foregroundStyle(RivaColor.textPrimary)
                    Text("mg in system")
                        .font(RivaFont.metricUnit)
                        .foregroundStyle(RivaColor.textSecondary)
                }

                RivaProgressBar(progress: estimate.gaugeFraction, height: 6)

                Text(estimate.explanation)
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    MedicationLevelCard(estimate: MockHomeRepository.snapshot().medicationLevel)
        .padding()
        .background(RivaColor.background)
}
