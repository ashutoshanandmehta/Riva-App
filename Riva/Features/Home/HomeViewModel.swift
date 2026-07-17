import Foundation
import Observation

/// Drives the Home dashboard: loads the snapshot and exposes display-ready
/// values so views stay declarative.
@MainActor
@Observable
final class HomeViewModel {

    enum State: Equatable {
        case loading
        case loaded(HomeSnapshot)
        case failed(message: String)
    }

    private(set) var state: State = .loading
    private let repository: any HomeRepository

    init(repository: any HomeRepository) {
        self.repository = repository
    }

    func load() async {
        // Keep already-loaded content on screen during a refresh.
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await repository.homeSnapshot())
        } catch is CancellationError {
            // View disappeared mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Couldn't load your dashboard. Pull to retry.")
        }
    }

    // MARK: - Display helpers

    /// "Good morning" / "Good afternoon" / "Good evening" by local time.
    static func greeting(for date: Date = .now, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

// Shared display formatting lives in `Core/Support/RivaFormat.swift`.
