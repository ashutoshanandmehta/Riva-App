import Foundation
import Observation

/// Drives the Wellness tab: loads the dashboard (summary + suggestions) and
/// records completed sessions with an optimistic hero update.
@MainActor
@Observable
final class WellnessViewModel {

    enum State {
        case loading
        case loaded(WellnessDashboard)
        case failed(message: String)
    }

    private(set) var state: State = .loading
    private let repository: any WellnessRepository
    private let logRepository: any LogRepository

    init(repository: any WellnessRepository, logRepository: any LogRepository) {
        self.repository = repository
        self.logRepository = logRepository
    }

    /// True once the backend has confirmed wellness support — gates the
    /// "Mark complete" affordance (silent degrade against an old backend).
    var canLogSessions: Bool {
        if case .loaded(let dashboard) = state { return dashboard.canLogSessions }
        return false
    }

    func load() async {
        // Keep already-loaded content on screen during a refresh.
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await repository.dashboard())
        } catch is CancellationError {
            // View disappeared mid-load; nothing to surface.
        } catch {
            state = .failed(message: "Couldn't load your wellness data. Pull to retry.")
        }
    }

    /// Logs a completed session; on success the hero numbers update
    /// optimistically from the server's response. Returns success.
    func markComplete(_ practice: WellnessPractice) async -> Bool {
        do {
            let result = try await logRepository.logWellnessSession(
                practiceId: practice.id,
                kind: practice.kind,
                minutes: practice.minutes
            )
            if case .loaded(var dashboard) = state {
                dashboard.summary.minutesToday = result.minutesToday
                dashboard.summary.streakDays = result.streakDays
                state = .loaded(dashboard)
            }
            return true
        } catch {
            return false
        }
    }

    /// Reflects a freshly saved minutes goal without a full reload.
    func applyGoal(minutes: Int) {
        guard case .loaded(var dashboard) = state else { return }
        dashboard.summary.goalMinutes = minutes
        state = .loaded(dashboard)
    }
}
