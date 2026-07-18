import Foundation
import Observation

/// Drives the Tracker tab: loads the dashboard snapshot from the repository
/// and exposes it to the view.
@MainActor
@Observable
final class TrackerViewModel {

    enum State: Equatable {
        case loading
        case loaded(TrackerDashboard)
        case failed(message: String)
    }

    private(set) var state: State = .loading
    private let repository: any TrackerRepository

    init(repository: any TrackerRepository) {
        self.repository = repository
    }

    func load() async {
        // Keep already-loaded content on screen during a refresh.
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await repository.trackerDashboard())
        } catch is CancellationError {
            // View disappeared mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Couldn't load your tracker. Pull to retry.")
        }
    }
}
