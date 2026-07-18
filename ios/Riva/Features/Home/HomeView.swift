import SwiftUI

/// Home dashboard — greeting, weight trend, medication model, next shot,
/// insight, and daily nutrients.
struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: HomeViewModel

    init(repository: any HomeRepository) {
        _viewModel = State(initialValue: HomeViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .loading:
                loadingState
            case .failed(let message):
                failedState(message)
            case .loaded(let snapshot):
                content(snapshot)
            }
        }
        .background(RivaColor.background)
        .contentMargins(.bottom, RivaLayout.tabBarClearance, for: .scrollContent)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    // MARK: Loaded

    private func content(_ snapshot: HomeSnapshot) -> some View {
        LazyVStack(spacing: RivaSpacing.md) {
            HomeHeader(
                userName: snapshot.user.firstName,
                quote: snapshot.quote,
                onSettings: { appModel.showProfile() }
            )

            WeightTrackingCard(summary: snapshot.weight)

            MedicationLevelCard(estimate: snapshot.medicationLevel)

            NextShotCard(shot: snapshot.nextShot) {
                appModel.activeDetail = .shotHistory
            }

            Button("Log today's shot") {
                appModel.activeQuickLog = .shot
            }
            .buttonStyle(.rivaPrimary)

            RivaInsightCard(insight: snapshot.insight)

            DailyNutrientsSection(nutrients: snapshot.nutrients)
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
    }

    // MARK: Loading / error

    private var loadingState: some View {
        LoadingStateView(message: "Loading your day…")
    }

    private func failedState(_ message: String) -> some View {
        ErrorStateView(message: message) {
            Task { await viewModel.load() }
        }
    }
}

#Preview {
    HomeView(repository: MockHomeRepository())
        .environment(AppModel())
}
