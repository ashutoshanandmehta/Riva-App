import SwiftUI

/// Protein goal tile — grams vs goal with a progress bar and a quick-add
/// button.
struct ProteinGoalCard: View {
    let protein: ProteinStatus
    /// Quick-add protein (placeholder for now).
    let onAdd: () -> Void

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Text("Protein goal")
                    .rivaOverline()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(RivaFormat.grams(protein.grams))g")
                        .font(RivaFont.metricM)
                        .foregroundStyle(RivaColor.textPrimary)
                    Text("/ \(RivaFormat.grams(protein.goalGrams))g")
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textSecondary)
                }

                Spacer()

                HStack(alignment: .center, spacing: RivaSpacing.sm) {
                    VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                        RivaProgressBar(progress: protein.progress, height: 7)
                        Text("\(RivaFormat.grams(protein.gramsRemaining))g remaining")
                            .font(.system(size: 12))
                            .foregroundStyle(RivaColor.textSecondary)
                    }

                    RivaQuickAddButton(accessibilityLabel: "Add protein", action: onAdd)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Protein: \(RivaFormat.grams(protein.grams)) of \(RivaFormat.grams(protein.goalGrams)) grams, \(RivaFormat.grams(protein.gramsRemaining)) grams remaining"
        )
    }
}

#Preview {
    ProteinGoalCard(protein: MockTrackerRepository.dashboard().protein) {}
        .frame(width: 170, height: 155)
        .padding()
        .background(RivaColor.background)
}
