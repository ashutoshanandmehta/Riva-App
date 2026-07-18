import Foundation
import Observation

/// Drives the Profile screen.
@MainActor
@Observable
final class ProfileViewModel {

    enum State: Equatable {
        case loading
        case loaded(ProfileSnapshot)
        case failed(message: String)
    }

    private(set) var state: State = .loading
    private let repository: any ProfileRepository

    init(repository: any ProfileRepository) {
        self.repository = repository
    }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await repository.profile())
        } catch is CancellationError {
            // View disappeared mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Couldn't load your profile. Pull to retry.")
        }
    }

}
