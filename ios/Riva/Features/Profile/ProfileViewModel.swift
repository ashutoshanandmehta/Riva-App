import Foundation
import Observation

/// Drives the Profile screen off the account bundle (profile, goals, plan).
@MainActor
@Observable
final class ProfileViewModel {

    enum State: Equatable {
        case loading
        case loaded(AccountBundle)
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
            state = .loaded(try await account.me())
        } catch is CancellationError {
            // View disappeared mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Could not load your profile. Try again.")
        }
    }
}
