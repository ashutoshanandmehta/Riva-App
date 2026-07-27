import SwiftUI

/// Destinations reachable from the Tracker tab.
enum TrackerRoute: Hashable {
    case weeklySummary
}

/// Tracker tab — weight trend and goal progress, calories, hydration,
/// protein, side effects, and sleep quality.
struct TrackerView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: TrackerViewModel
    @State private var path: [TrackerRoute] = []
    private let repository: any TrackerRepository

    init(repository: any TrackerRepository) {
        self.repository = repository
        _viewModel = State(initialValue: TrackerViewModel(repository: repository))

        #if DEBUG
        // UI-test / screenshot hook: `-riva.trackerRoute weeklySummary`.
        if UserDefaults.standard.string(forKey: "riva.trackerRoute") == "weeklySummary" {
            _path = State(initialValue: [.weeklySummary])
        }
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            dashboard
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: TrackerRoute.self) { route in
                    switch route {
                    case .weeklySummary:
                        WeeklySummaryView(repository: repository)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            // Pinned: the brand bar stays put while the tab scrolls under it.
            BrandTopBar(onSettings: { appModel.showProfile() })
                .padding(.horizontal, TPCSpacing.screenMargin)
                .padding(.top, TPCSpacing.xs)

            ScrollView {
                switch viewModel.state {
                case .loading:
                    LoadingStateView(message: "Loading your tracker…")
                case .failed(let message):
                    ErrorStateView(message: message) {
                        Task { await viewModel.load() }
                    }
                case .loaded(let dashboard):
                    content(dashboard)
                }
            }
        }
        .background(TPCColor.background)
        .contentMargins(.bottom, TPCLayout.tabBarClearance, for: .scrollContent)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .onChange(of: appModel.dashboardRevision) {
            // Apply the fresh totals in place for an instant update, then
            // reconcile against the server in the background.
            if let totals = appModel.pendingTotals {
                viewModel.apply(totals: totals)
            }
            Task { await viewModel.load() }
        }
    }

    // MARK: Loaded

    private func content(_ dashboard: TrackerDashboard) -> some View {
        // Cards size to their content, as on every other tab — a pinned height
        // squeezes the "… remaining" rows and truncates them mid-word.
        LazyVStack(alignment: .leading, spacing: TPCSpacing.lg) {
            WeightTrackingCard(summary: dashboard.weight) {
                appModel.activeDetail = .weightHistory
            }

            CalorieCard(
                calorie: dashboard.calorie,
                onOpen: { appModel.activeDetail = .caloriesHistory },
                onAdd: { appModel.activeQuickLog = .calories }
            )

            HStack(spacing: TPCSpacing.lg) {
                HydrationCard(
                    hydration: dashboard.hydration,
                    onOpen: { appModel.activeDetail = .hydrationHistory },
                    onAdd: { appModel.activeQuickLog = .water }
                )
                ProteinGoalCard(
                    protein: dashboard.protein,
                    onOpen: { appModel.activeDetail = .proteinHistory },
                    onAdd: { appModel.activeQuickLog = .protein }
                )
            }

            HStack(spacing: TPCSpacing.lg) {
                SideEffectsCard(
                    report: dashboard.sideEffect,
                    onOpen: { appModel.activeDetail = .sideEffectsHistory },
                    onAdd: { appModel.activeQuickLog = .sideEffects }
                )
                SleepQualityCard(sleep: dashboard.sleep) {
                    appModel.activeQuickLog = .sleep
                }
            }

            Button {
                path.append(.weeklySummary)
            } label: {
                HStack {
                    Spacer()
                    Text("View Weekly Summary")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(.horizontal, TPCSpacing.xs)
            }
            .buttonStyle(.rivaPrimary)
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.top, TPCSpacing.xs)
    }
}

#Preview {
    TrackerView(repository: MockTrackerRepository())
        .environment(AppModel())
}
