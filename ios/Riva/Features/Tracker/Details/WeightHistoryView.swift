import SwiftUI

/// Weight history sheet: every logged weight, newest first, with an
/// overall change summary once there are two or more entries.
struct WeightHistoryView: View {
    let onClose: () -> Void

    @State private var model: WeightHistoryViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: WeightHistoryViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailSheetHeader(title: "Weight History", onClose: onClose)

            ScrollView {
                switch model.state {
                case .loading:
                    LoadingStateView(message: "Loading your weights…")
                case .failed(let message):
                    ErrorStateView(message: message) {
                        Task { await model.load() }
                    }
                case .loaded(let entries):
                    if entries.isEmpty {
                        DetailEmptyState(
                            systemImage: "scalemass",
                            message: "No weights logged yet. Use the snap menu to log one."
                        )
                    } else {
                        list(entries)
                    }
                }
            }
        }
        .padding(.top, RivaSpacing.sm)
        .task { await model.load() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
    }

    // MARK: List

    private func list(_ entries: [WeightEntry]) -> some View {
        LazyVStack(spacing: RivaSpacing.sm) {
            summaryStrip(entries)
            ForEach(entries) { entry in
                weightCard(entry)
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
        .padding(.bottom, RivaSpacing.xl)
    }

    /// Change since the earliest entry, shown once there is a trend to tell.
    @ViewBuilder
    private func summaryStrip(_ entries: [WeightEntry]) -> some View {
        if entries.count >= 2, let newest = entries.first, let oldest = entries.last {
            let delta = newest.pounds - oldest.pounds
            RivaCard(style: .tinted) {
                HStack(spacing: RivaSpacing.xs) {
                    Image(systemName: deltaIcon(delta))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RivaColor.brand)
                    Text(deltaText(delta, since: DetailDate.shortDayLabel(oldest.measuredAt)))
                        .font(RivaFont.captionEmphasized)
                        .foregroundStyle(RivaColor.textPrimary)
                }
            }
        }
    }

    private func deltaIcon(_ delta: Double) -> String {
        if abs(delta) < 0.05 { return "arrow.right" }
        return delta < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private func deltaText(_ delta: Double, since: String) -> String {
        if abs(delta) < 0.05 { return "Holding steady since \(since)" }
        let direction = delta < 0 ? "Down" : "Up"
        return "\(direction) \(RivaFormat.weight(abs(delta))) lbs since \(since)"
    }

    private func weightCard(_ entry: WeightEntry) -> some View {
        RivaCard {
            HStack {
                VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: RivaSpacing.xxs) {
                        Text(RivaFormat.weight(entry.pounds))
                            .font(RivaFont.metricM)
                            .foregroundStyle(RivaColor.textPrimary)
                        Text("lbs")
                            .font(RivaFont.metricUnit)
                            .foregroundStyle(RivaColor.textSecondary)
                    }
                    Text(DetailDate.dayLabel(entry.measuredAt))
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textSecondary)
                }
                Spacer()
                if let dose = entry.doseMg {
                    RivaBadge(text: "on \(RivaFormat.doseMg(dose))")
                }
            }
        }
    }
}

/// Loads the weight list for the history sheet.
@MainActor
@Observable
final class WeightHistoryViewModel {

    enum State: Equatable {
        case loading
        case loaded([WeightEntry])
        case failed(message: String)
    }

    private(set) var state: State = .loading
    private let account: any AccountRepository

    init(account: any AccountRepository) {
        self.account = account
    }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let entries = try await account.weights().sorted {
                (DetailDate.parse($0.measuredAt) ?? .distantPast)
                    > (DetailDate.parse($1.measuredAt) ?? .distantPast)
            }
            state = .loaded(entries)
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Could not load your weights. Try again.")
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        WeightHistoryView(account: MockAccountRepository()) {}
    }
}
