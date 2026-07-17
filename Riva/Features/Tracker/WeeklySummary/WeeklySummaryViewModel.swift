import Foundation
import Observation

/// Drives the Weekly Summary screen.
@MainActor
@Observable
final class WeeklySummaryViewModel {

    enum State: Equatable {
        case loading
        case loaded(WeeklySummary)
        case failed(message: String)
    }

    private(set) var state: State = .loading
    private let repository: any TrackerRepository

    init(repository: any TrackerRepository) {
        self.repository = repository
    }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await repository.weeklySummary())
        } catch is CancellationError {
            // View disappeared mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Couldn't load your weekly summary. Pull to retry.")
        }
    }
}
