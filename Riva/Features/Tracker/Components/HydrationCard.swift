import SwiftUI

/// Hydration tile — the card itself "fills" with water to the day's
/// progress, with a quick-add button.
struct HydrationCard: View {
    let hydration: HydrationStatus
    /// Quick-add a glass (placeholder for now).
    let onAdd: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RivaColor.surface

                // Water level.
                LinearGradient(
                    colors: [RivaColor.brandSoft.opacity(0.45), RivaColor.brandSoft],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * hydration.progress)

                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous))
        .rivaSurfaceOutline(cornerRadius: RivaRadius.card)
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hydration: \(hydration.glasses) of \(hydration.goalGlasses) glasses")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text("Hydration")
                .rivaOverline()

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(hydration.glasses)")
                    .font(RivaFont.metricM)
                    .foregroundStyle(RivaColor.textPrimary)
                Text("/ \(hydration.goalGlasses) glasses")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }

            Spacer()

            HStack {
                Spacer()
                RivaQuickAddButton(accessibilityLabel: "Add a glass of water", action: onAdd)
            }
        }
        .padding(RivaSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    HydrationCard(hydration: MockTrackerRepository.dashboard().hydration) {}
        .frame(width: 170, height: 155)
        .padding()
        .background(RivaColor.background)
}
