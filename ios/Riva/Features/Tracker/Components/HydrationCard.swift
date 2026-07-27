import SwiftUI

/// Hydration tile — the card itself "fills" with water to the day's
/// progress, with a quick-add button.
struct HydrationCard: View {
    let hydration: HydrationStatus
    /// Opens the hydration history sheet.
    let onOpen: () -> Void
    /// Quick-add a glass (placeholder for now).
    let onAdd: () -> Void

    var body: some View {
        // The water level reads the card's height from behind the content: a
        // GeometryReader in `.background` measures its parent instead of
        // defining it, so the card still sizes to what's inside it.
        content
            .background {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        TPCColor.surface

                        // Water level.
                        LinearGradient(
                            colors: [TPCColor.brandSoft.opacity(0.45), TPCColor.brandSoft],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: proxy.size.height * hydration.progress)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous))
            .rivaSurfaceOutline(cornerRadius: TPCRadius.card)
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Hydration: \(hydration.glasses) of \(hydration.goalGlasses) glasses"
            )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
            HStack {
                Text("Hydration")
                    .rivaOverline()
                Spacer()
                HistoryChevronButton(accessibilityLabel: "Hydration history", action: onOpen)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(hydration.glasses)")
                    .font(TPCFont.metricM)
                    .foregroundStyle(TPCColor.textPrimary)
                Text("/ \(hydration.goalGlasses) glasses")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
            }

            Spacer()

            HStack {
                Spacer()
                RivaQuickAddButton(accessibilityLabel: "Add a glass of water", action: onAdd)
            }
        }
        // Matches RivaCard's inset so this tile and its row-mate line up.
        .padding(TPCSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    HydrationCard(hydration: MockTrackerRepository.dashboard().hydration, onOpen: {}, onAdd: {})
        .frame(width: 170)
        .padding()
        .background(TPCColor.background)
}
