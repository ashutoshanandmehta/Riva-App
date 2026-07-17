import SwiftUI

/// Destinations reachable from the Tracker tab.
enum TrackerRoute: Hashable {
    case weeklySummary
}

/// Tracker tab — coaching intelligence, weight trend, hydration, protein,
/// side effects, and sleep quality.
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
        .background(RivaColor.background)
        .contentMargins(.bottom, RivaLayout.tabBarClearance, for: .scrollContent)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    // MARK: Loaded

    private func content(_ dashboard: TrackerDashboard) -> some View {
        LazyVStack(alignment: .leading, spacing: RivaSpacing.md) {
            BrandTopBar {
                appModel.showProfile()
            }

            IntelligenceBanner(insight: dashboard.intelligence)

            CurrentWeightCard(trend: dashboard.weight) {
                appModel.present(placeholder: .weightDetails)
            }

            HStack(spacing: RivaSpacing.md) {
                HydrationCard(hydration: dashboard.hydration) {
                    appModel.activeScanMode = .water
                }
                ProteinGoalCard(protein: dashboard.protein) {
                    appModel.activeQuickLog = .protein
                }
            }
            .frame(height: 155)

            HStack(spacing: RivaSpacing.md) {
                SideEffectsCard(
                    report: dashboard.sideEffect,
                    onOpen: { appModel.present(placeholder: .sideEffects) },
                    onAdd: { appModel.activeQuickLog = .sideEffects }
                )
                SleepQualityCard(sleep: dashboard.sleep) {
                    appModel.activeQuickLog = .sleep
                }
            }
            .frame(height: 200)

            Button {
                path.append(.weeklySummary)
            } label: {
                HStack {
                    Spacer()
                    Text("View Weekly Summary")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(.horizontal, RivaSpacing.xs)
            }
            .buttonStyle(.rivaPrimary)
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
    }
}

#Preview {
    TrackerView(repository: MockTrackerRepository())
        .environment(AppModel())
}
