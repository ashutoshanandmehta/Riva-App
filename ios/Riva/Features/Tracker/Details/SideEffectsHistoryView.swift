import SwiftUI

/// Side-effect history sheet: one card per logged day, newest first, with
/// a severity chip for each reported effect.
struct SideEffectsHistoryView: View {
    let onClose: () -> Void

    @State private var model: SideEffectsHistoryViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: SideEffectsHistoryViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailSheetHeader(title: "Side Effects", onClose: onClose)

            ScrollView {
                switch model.state {
                case .loading:
                    LoadingStateView(message: "Loading your side effects…")
                case .failed(let message):
                    ErrorStateView(message: message) {
                        Task { await model.load() }
                    }
                case .loaded(let days):
                    if days.isEmpty {
                        DetailEmptyState(
                            systemImage: "exclamationmark.bubble",
                            message: "Nothing logged in the last 30 days."
                        )
                    } else {
                        list(days)
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

    private func list(_ days: [SideEffectDayLog]) -> some View {
        LazyVStack(spacing: RivaSpacing.sm) {
            ForEach(days) { day in
                dayCard(day)
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
        .padding(.bottom, RivaSpacing.xl)
    }

    private func dayCard(_ day: SideEffectDayLog) -> some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                Text(DetailDate.dayLabel(day.logDate))
                    .font(RivaFont.cardTitle)
                    .foregroundStyle(RivaColor.textPrimary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 112), spacing: RivaSpacing.xs, alignment: .leading)],
                    alignment: .leading,
                    spacing: RivaSpacing.xs
                ) {
                    ForEach(day.effects, id: \.effect) { entry in
                        severityChip(entry)
                    }
                }

                if let note = day.note, !note.isEmpty {
                    Text(note)
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textSecondary)
                }
            }
        }
    }

    /// Mild reads neutral, moderate reads brand, severe borrows the scan
    /// mismatch banner's warning treatment.
    @ViewBuilder
    private func severityChip(_ entry: SideEffectEntry) -> some View {
        let label = "\(effectName(entry.effect)) \(entry.severity)"
        switch entry.severity {
        case ...2:
            RivaBadge(text: label)
        case 3:
            RivaBadge(text: label, style: .brand)
        default:
            Text(label)
                .rivaOverline(RivaColor.warning)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(RivaColor.warning.opacity(0.12), in: Capsule())
        }
    }

    private func effectName(_ raw: String) -> String {
        SideEffect(rawValue: raw)?.title
            ?? raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Loads the recent side-effect days for the history sheet.
@MainActor
@Observable
final class SideEffectsHistoryViewModel {

    enum State: Equatable {
        case loading
        case loaded([SideEffectDayLog])
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
            let days = try await account.sideEffects().sorted {
                (DetailDate.parse($0.logDate) ?? .distantPast)
                    > (DetailDate.parse($1.logDate) ?? .distantPast)
            }
            state = .loaded(days)
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Could not load your side effects. Try again.")
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        SideEffectsHistoryView(account: MockAccountRepository()) {}
    }
}
