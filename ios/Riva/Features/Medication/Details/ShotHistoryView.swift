import SwiftUI

/// Shot history sheet: every logged shot, newest first.
struct ShotHistoryView: View {
    let onClose: () -> Void

    @State private var model: ShotHistoryViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: ShotHistoryViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailSheetHeader(title: "Shot History", onClose: onClose)

            ScrollView {
                switch model.state {
                case .loading:
                    LoadingStateView(message: "Loading your shots…")
                case .failed(let message):
                    ErrorStateView(message: message) {
                        Task { await model.load() }
                    }
                case .loaded(let shots):
                    if shots.isEmpty {
                        DetailEmptyState(
                            systemImage: "syringe",
                            message: "No shots logged yet. Log your first from the Medication tab."
                        )
                    } else {
                        list(shots)
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

    private func list(_ shots: [ShotEntry]) -> some View {
        LazyVStack(spacing: RivaSpacing.sm) {
            ForEach(shots) { shot in
                shotCard(shot)
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
        .padding(.bottom, RivaSpacing.xl)
    }

    private func shotCard(_ shot: ShotEntry) -> some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                HStack(alignment: .top) {
                    Text("\(shot.medicationName) \(RivaFormat.doseMg(shot.doseMg))")
                        .font(RivaFont.cardTitle)
                        .foregroundStyle(RivaColor.textPrimary)
                    Spacer()
                    if let rating = shot.comfortRating {
                        RivaBadge(text: "Comfort \(rating) of 5", style: .brand)
                    }
                }

                Text(DetailDate.dayLabel(shot.takenAt))
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)

                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RivaColor.brand)
                    Text(siteName(shot.injectionSite))
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textSecondary)
                }
            }
        }
    }

    private func siteName(_ raw: String) -> String {
        InjectionSite(rawValue: raw)?.title
            ?? raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Loads the shot list for the history sheet.
@MainActor
@Observable
final class ShotHistoryViewModel {

    enum State: Equatable {
        case loading
        case loaded([ShotEntry])
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
            let shots = try await account.shots().sorted {
                (DetailDate.parse($0.takenAt) ?? .distantPast)
                    > (DetailDate.parse($1.takenAt) ?? .distantPast)
            }
            state = .loaded(shots)
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Could not load your shots. Try again.")
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ShotHistoryView(account: MockAccountRepository()) {}
    }
}
