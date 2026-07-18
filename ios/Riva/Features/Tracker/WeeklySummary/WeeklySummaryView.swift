import SwiftUI

/// Weekly Summary — pushed from the Tracker tab. Week-scoped weight
/// progress, coach note, medication dates, nutrition, hydration, and sleep.
struct WeeklySummaryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WeeklySummaryViewModel

    init(repository: any TrackerRepository) {
        _viewModel = State(initialValue: WeeklySummaryViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .loading:
                LoadingStateView(message: "Preparing your summary…")
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await viewModel.load() }
                }
            case .loaded(let summary):
                content(summary)
            }
        }
        .background(RivaColor.background)
        .contentMargins(.bottom, RivaLayout.tabBarClearance, for: .scrollContent)
        .task { await viewModel.load() }
    }

    // MARK: Loaded

    private func content(_ summary: WeeklySummary) -> some View {
        LazyVStack(alignment: .leading, spacing: RivaSpacing.md) {
            BrandTopBar(
                onBack: { dismiss() },
                onSettings: { appModel.showProfile() }
            )

            VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                Text("Weekly Summary")
                    .font(RivaFont.screenTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text(RivaFormat.weekRange(summary.interval))
                    .rivaOverline()
            }

            WeightProgressCard(progress: summary.weight)

            CoachNoteCard(note: summary.coachNote)

            MedicationWeekSection(
                lastDose: summary.lastDoseDate,
                nextDose: summary.nextDoseDate,
                onManage: {
                    // Real navigation: pop and jump to the Medication tab.
                    dismiss()
                    appModel.select(tab: .medication)
                }
            )

            NutritionOverviewCard(calories: summary.calories, protein: summary.protein)

            HStack(spacing: RivaSpacing.md) {
                SummaryStatTile(
                    systemImage: "drop",
                    caption: "Hydration",
                    value: RivaFormat.litersPerDay(summary.hydrationLitersPerDay)
                )
                SummaryStatTile(
                    systemImage: "moon",
                    caption: "Sleep avg",
                    value: summary.sleepAverageMinutes > 0
                        ? RivaFormat.sleepDuration(minutes: summary.sleepAverageMinutes)
                        : "Not logged"
                )
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
    }
}

#Preview {
    NavigationStack {
        WeeklySummaryView(repository: MockTrackerRepository())
            .environment(AppModel())
    }
}
