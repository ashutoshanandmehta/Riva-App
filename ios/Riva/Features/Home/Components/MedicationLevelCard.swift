import SwiftUI

/// Estimated active-drug level card ("1.8 mg in system") with a level gauge.
struct MedicationLevelCard: View {
    let estimate: MedicationLevelEstimate

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                HStack(spacing: TPCSpacing.xs) {
                    RivaIconChip(systemImage: "syringe")
                    Text("Medication level")
                        .font(TPCFont.cardTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Spacer()
                    RivaBadge(text: "Estimated")
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", estimate.currentMg))
                        .font(TPCFont.metricXL)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text("mg in system")
                        .font(TPCFont.metricUnit)
                        .foregroundStyle(TPCColor.textSecondary)
                }

                RivaProgressBar(progress: estimate.gaugeFraction, height: 6)

                Text(estimate.explanation)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    MedicationLevelCard(estimate: MockHomeRepository.snapshot().medicationLevel)
        .padding()
        .background(TPCColor.background)
}
