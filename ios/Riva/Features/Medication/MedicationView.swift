import SwiftUI

/// Medication tab — titration status, next dose, concentration curve, and
/// dose history.
struct MedicationView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: MedicationViewModel

    init(repository: any MedicationRepository) {
        _viewModel = State(initialValue: MedicationViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .loading:
                LoadingStateView(message: "Loading your plan…")
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

    private func content(_ dashboard: MedicationDashboard) -> some View {
        LazyVStack(alignment: .leading, spacing: RivaSpacing.md) {
            BrandTopBar {
                appModel.showProfile()
            }

            header(dashboard)

            CurrentDoseCard(titration: dashboard.titration, nextDose: dashboard.nextDose)

            Button {
                appModel.activeQuickLog = .shot
            } label: {
                HStack(spacing: RivaSpacing.xs) {
                    Image(systemName: "syringe")
                    Text("Log Weekly Shot")
                }
            }
            .buttonStyle(.rivaPrimary)

            MedicationCurveCard(curve: dashboard.curve, insight: dashboard.insight) {
                appModel.activeDetail = .curveInfo
            }

            DoseHistorySection(records: dashboard.history) { _ in
                appModel.activeDetail = .shotHistory
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
    }

    private func header(_ dashboard: MedicationDashboard) -> some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text("Medication")
                .font(RivaFont.screenTitle)
                .foregroundStyle(RivaColor.textPrimary)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RivaColor.brand)
                Text("Injection Day: \(RivaFormat.weekdayName(dashboard.nextDose.date))")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
    }
}

#Preview {
    MedicationView(repository: MockMedicationRepository())
        .environment(AppModel())
}
