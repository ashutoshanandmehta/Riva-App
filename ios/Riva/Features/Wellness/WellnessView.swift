import SwiftUI

/// Wellness tab — greeting, minutes-practiced hero, the practice catalog,
/// and personalized suggestions.
struct WellnessView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: WellnessViewModel
    private let account: any AccountRepository

    @State private var selectedPractice: WellnessPractice?
    @State private var showSeeAll = false
    @State private var showGoalSheet = false

    init(
        repository: any WellnessRepository,
        logRepository: any LogRepository,
        account: any AccountRepository
    ) {
        _viewModel = State(initialValue: WellnessViewModel(
            repository: repository,
            logRepository: logRepository
        ))
        self.account = account
    }

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .loading:
                LoadingStateView(message: "Loading your practices…")
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await viewModel.load() }
                }
            case .loaded(let dashboard):
                content(dashboard)
            }
        }
        .background(TPCColor.background)
        .contentMargins(.bottom, TPCLayout.tabBarClearance, for: .scrollContent)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .onChange(of: appModel.dashboardRevision) {
            Task { await viewModel.load() }
        }
        .sheet(isPresented: $showSeeAll) {
            WellnessCategorySheet(markComplete: markCompleteHandler)
        }
        .sheet(isPresented: $showGoalSheet) {
            WellnessGoalSheet(account: account, currentGoal: currentGoal) { minutes in
                viewModel.applyGoal(minutes: minutes)
            }
        }
        .fullScreenCover(item: $selectedPractice) { practice in
            PracticeDetailView(
                practice: practice,
                markComplete: markCompleteHandler.map { complete in
                    { await complete(practice) }
                }
            )
        }
    }

    // MARK: Loaded

    private func content(_ dashboard: WellnessDashboard) -> some View {
        LazyVStack(alignment: .leading, spacing: TPCSpacing.md) {
            BrandTopBar(onSettings: { appModel.showProfile() })

            Text("How would you like\nto feel today?")
                .font(TPCFont.screenTitle)
                .foregroundStyle(TPCColor.textPrimary)
                .padding(.top, TPCSpacing.xs)

            WellnessHeroCard(
                summary: dashboard.summary,
                onStart: { selectedPractice = startPractice(dashboard) },
                // Only allow editing the goal when the backend can persist it;
                // against an old backend the numeral is shown but not tappable.
                onEditGoal: viewModel.canLogSessions ? { showGoalSheet = true } : nil
            )

            practicesSection

            suggestionsSection(dashboard.suggestions)
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.top, TPCSpacing.xs)
    }

    // MARK: Your practices

    private var practicesSection: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            HStack {
                Text("Your practices")
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Spacer()
                Button("See all") { showSeeAll = true }
                    .font(TPCFont.captionEmphasized)
                    .foregroundStyle(TPCColor.brand)
            }
            .padding(.top, TPCSpacing.xs)

            if let yoga = WellnessPractice.practice(id: "yoga_beginners") {
                PracticeRowCard(practice: yoga) { selectedPractice = yoga }
            }

            HStack(alignment: .top, spacing: TPCSpacing.md) {
                tile(id: "exercise_walk")
                tile(id: "meditation_isha")
            }
        }
    }

    @ViewBuilder
    private func tile(id: String) -> some View {
        if let practice = WellnessPractice.practice(id: id) {
            PracticeTileCard(practice: practice) { selectedPractice = practice }
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Suggested for you

    @ViewBuilder
    private func suggestionsSection(_ suggestions: [SuggestedPractice]) -> some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                Text("Suggested for you")
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                    .padding(.top, TPCSpacing.xs)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: TPCSpacing.md) {
                        ForEach(suggestions) { suggestion in
                            SuggestedPracticeCard(suggestion: suggestion) {
                                selectedPractice = suggestion.practice
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: Helpers

    /// "Start session" opens the top suggestion, or the first yoga flow.
    private func startPractice(_ dashboard: WellnessDashboard) -> WellnessPractice? {
        dashboard.suggestions.first?.practice
            ?? WellnessPractice.catalog.first { $0.kind == .yoga }
    }

    private var currentGoal: Int {
        if case .loaded(let dashboard) = viewModel.state {
            return dashboard.summary.goalMinutes
        }
        return 45
    }

    /// Non-nil only when the backend confirmed wellness support; a nil
    /// handler hides "Mark complete" everywhere downstream.
    private var markCompleteHandler: ((WellnessPractice) async -> Bool)? {
        guard viewModel.canLogSessions else { return nil }
        return { practice in
            let ok = await viewModel.markComplete(practice)
            if ok { appModel.refreshDashboards() }
            return ok
        }
    }
}

#Preview {
    WellnessView(
        repository: MockWellnessRepository(),
        logRepository: MockLogRepository(),
        account: MockAccountRepository()
    )
    .environment(AppModel())
}
