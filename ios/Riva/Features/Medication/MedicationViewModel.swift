import Foundation
import Observation

/// Drives the Medication tab: loads the dashboard snapshot from the
/// repository and exposes it to the view.
@MainActor
@Observable
final class MedicationViewModel {

    enum State: Equatable {
        case loading
        case loaded(MedicationDashboard)
        case failed(message: String)
    }

    private(set) var state: State = .loading
    private let repository: any MedicationRepository

    init(repository: any MedicationRepository) {
        self.repository = repository
    }

    func load() async {
        // Keep already-loaded content on screen during a refresh.
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await repository.medicationDashboard())
        } catch is CancellationError {
            // View disappeared mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Couldn't load your medication plan. Pull to retry.")
        }
    }
}
