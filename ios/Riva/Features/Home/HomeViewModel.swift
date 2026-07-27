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

    /// Optimistically folds a fresh log's totals into the loaded snapshot so the
    /// calorie ring and macro bars update instantly, ahead of the background
    /// refetch. Each tile keeps its own goal, so only the consumed value moves.
    /// No-op unless already loaded.
    func apply(totals: DayTotals) {
        guard case .loaded(var snapshot) = state else { return }
        snapshot.nutrients = snapshot.nutrients.map { tile in
            var updated = tile
            switch tile.title {
            case "Calories": updated.value = Double(totals.calories)
            case "Protein":  updated.value = Double(totals.proteinGrams)
            case "Carbs":    updated.value = Double(totals.carbGrams)
            case "Fiber":    updated.value = Double(totals.fiberGrams)
            default:         break
            }
            return updated
        }
        // The day now has activity, so today's week-strip cell ticks with the
        // tiles rather than lagging until the refetch lands. The first log of
        // the day also extends the streak by exactly one: the server anchors an
        // unlogged today on yesterday, so today's log continues that run.
        let wasLoggedToday = snapshot.week.first { $0.isToday }?.isLogged ?? true
        if totals.calories > 0 || totals.waterOunces > 0 {
            snapshot.week = snapshot.week.map { day in
                guard day.isToday else { return day }
                var updated = day
                updated.isLogged = true
                return updated
            }
            if !wasLoggedToday {
                snapshot.streakDays += 1
            }
        }
        state = .loaded(snapshot)
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
