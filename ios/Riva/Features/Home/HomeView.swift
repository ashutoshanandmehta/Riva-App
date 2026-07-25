import SwiftUI

/// Home dashboard — greeting, to-dos, medication model, next shot, and daily
/// nutrients. The weight trend lives on the Tracker tab.
struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: HomeViewModel
    private let todoRepository: any TodoRepository

    init(repository: any HomeRepository, todoRepository: any TodoRepository) {
        _viewModel = State(initialValue: HomeViewModel(repository: repository))
        self.todoRepository = todoRepository
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

    private func content(_ snapshot: HomeSnapshot) -> some View {
        LazyVStack(spacing: RivaSpacing.md) {
            HomeHeader(
                userName: snapshot.user.firstName,
                quote: snapshot.quote,
                onSettings: { appModel.showProfile() }
            )

            TodoSection(repository: todoRepository)

            MedicationLevelCard(estimate: snapshot.medicationLevel)

            NextShotCard(shot: snapshot.nextShot) {
                appModel.activeDetail = .shotHistory
            }

            Button("Log today's shot") {
                appModel.activeQuickLog = .shot
            }
            .buttonStyle(.rivaPrimary)

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
    HomeView(repository: MockHomeRepository(), todoRepository: MockTodoRepository())
        .environment(AppModel())
}
