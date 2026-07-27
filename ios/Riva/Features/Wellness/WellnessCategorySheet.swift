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
                LazyVStack(alignment: .leading, spacing: TPCSpacing.md) {
                    ForEach(WellnessKind.allCases, id: \.self) { kind in
                        let practices = WellnessPractice.catalog.filter { $0.kind == kind }
                        if !practices.isEmpty {
                            section(kind: kind, practices: practices)
                        }
                    }
                }
                .padding(.horizontal, TPCSpacing.screenMargin)
                .padding(.top, TPCSpacing.sm)
            }
            .navigationTitle("All practices")
            .navigationBarTitleDisplayMode(.large)
            .background(TPCColor.background)
            .toolbarBackground(TPCColor.background, for: .navigationBar)
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
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            Text(kind.title.uppercased())
                .rivaOverline(TPCColor.textSecondary)
                .padding(.top, TPCSpacing.xs)

            ForEach(practices) { practice in
                practiceRow(practice)
            }
        }
    }

    private func practiceRow(_ practice: WellnessPractice) -> some View {
        Button { selectedPractice = practice } label: {
            RivaCard {
                HStack(spacing: TPCSpacing.md) {
                    RivaIconChip(
                        systemImage: practice.icon,
                        tint: TPCColor.brand,
                        background: TPCColor.brandSoft,
                        size: 44
                    )
                    VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                        HStack(spacing: TPCSpacing.xs) {
                            Text(practice.title)
                                .font(TPCFont.cardTitle)
                                .foregroundStyle(TPCColor.textPrimary)
                            Text(practice.durationText.uppercased())
                                .rivaOverline(TPCColor.brand)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(TPCColor.brandWash, in: Capsule())
                        }
                        Text(practice.subtitle)
                            .font(TPCFont.footnote)
                            .foregroundStyle(TPCColor.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TPCColor.textTertiary)
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
