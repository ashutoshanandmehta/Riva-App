import SwiftUI

/// The "See all" sheet: the unified practice catalog grouped by kind.
/// `markComplete` is nil when the backend has no wellness support, which
/// hides the detail view's completion button.
struct WellnessCategorySheet: View {
    var markComplete: ((WellnessPractice) async -> Bool)?

    @State private var selectedPractice: WellnessPractice?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: RivaSpacing.md) {
                    ForEach(WellnessKind.allCases, id: \.self) { kind in
                        let practices = WellnessPractice.catalog.filter { $0.kind == kind }
                        if !practices.isEmpty {
                            section(kind: kind, practices: practices)
                        }
                    }
                }
                .padding(.horizontal, RivaSpacing.screenMargin)
                .padding(.top, RivaSpacing.sm)
            }
            .navigationTitle("All practices")
            .navigationBarTitleDisplayMode(.large)
            .background(RivaColor.background)
            .toolbarBackground(RivaColor.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $selectedPractice) { practice in
            PracticeDetailView(
                practice: practice,
                markComplete: markComplete.map { complete in
                    { await complete(practice) }
                }
            )
        }
    }

    private func section(kind: WellnessKind, practices: [WellnessPractice]) -> some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            Text(kind.title.uppercased())
                .rivaOverline(RivaColor.textSecondary)
                .padding(.top, RivaSpacing.xs)

            ForEach(practices) { practice in
                practiceRow(practice)
            }
        }
    }

    private func practiceRow(_ practice: WellnessPractice) -> some View {
        Button { selectedPractice = practice } label: {
            RivaCard {
                HStack(spacing: RivaSpacing.md) {
                    RivaIconChip(
                        systemImage: practice.icon,
                        tint: RivaColor.brand,
                        background: RivaColor.brandSoft,
                        size: 44
                    )
                    VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                        HStack(spacing: RivaSpacing.xs) {
                            Text(practice.title)
                                .font(RivaFont.cardTitle)
                                .foregroundStyle(RivaColor.textPrimary)
                            Text(practice.durationText.uppercased())
                                .rivaOverline(RivaColor.brand)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(RivaColor.brandWash, in: Capsule())
                        }
                        Text(practice.subtitle)
                            .font(RivaFont.footnote)
                            .foregroundStyle(RivaColor.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RivaColor.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        WellnessCategorySheet { _ in true }
    }
}
