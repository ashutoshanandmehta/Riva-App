import SwiftUI

/// Protein goal tile — grams vs goal with a progress bar and a quick-add
/// button.
struct ProteinGoalCard: View {
    let protein: ProteinStatus
    /// Opens the protein history sheet.
    let onOpen: () -> Void
    /// Quick-add protein (placeholder for now).
    let onAdd: () -> Void

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                HStack {
                    Text("Protein goal")
                        .rivaOverline()
                    Spacer()
                    HistoryChevronButton(accessibilityLabel: "Protein history", action: onOpen)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(RivaFormat.grams(protein.grams))g")
                        .font(TPCFont.metricM)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text("/ \(RivaFormat.grams(protein.goalGrams))g")
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                }

                Spacer()

                HStack(alignment: .center, spacing: TPCSpacing.sm) {
                    VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                        RivaProgressBar(progress: protein.progress, height: 7)
                        Text("\(RivaFormat.grams(protein.gramsRemaining))g remaining")
                            .font(.system(size: 12))
                            .foregroundStyle(TPCColor.textSecondary)
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
    ProteinGoalCard(protein: MockTrackerRepository.dashboard().protein, onOpen: {}, onAdd: {})
        .frame(width: 170)
        .padding()
        .background(TPCColor.background)
}
