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

    /// Optimistically folds a fresh log's totals into the loaded snapshot so
    /// the Protein, Water, and Calories nutrient tiles update instantly, ahead
    /// of the background refetch. Goals are read back from each tile's target
    /// text (the snapshot carries no raw goals), matching how
    /// `APIHomeRepository` builds the tiles. No-op unless already loaded.
    func apply(totals: DayTotals) {
        guard case .loaded(var snapshot) = state else { return }
        snapshot.nutrients = snapshot.nutrients.map { tile in
            var updated = tile
            let goal = Self.goalNumber(from: tile.targetText)
            switch tile.title {
            case "Protein":
                updated.valueText = "\(totals.proteinGrams)g"
                updated.progress = Self.progress(Double(totals.proteinGrams), goal)
            case "Water":
                // Target is in glasses; totals and progress are in ounces.
                updated.valueText = "\(totals.waterOunces / 8)"
                updated.progress = Self.progress(Double(totals.waterOunces), goal * 8)
            case "Calories":
                updated.valueText = "\(totals.calories)"
                updated.progress = Self.progress(Double(totals.calories), goal)
            default:
                break
            }
            return updated
        }
        state = .loaded(snapshot)
    }

    /// First integer in a tile's target text ("of 110g" → 110), the goal.
    private static func goalNumber(from targetText: String) -> Double {
        let digits = targetText.split(whereSeparator: { !$0.isNumber })
        return digits.first.flatMap { Double($0) } ?? 0
    }

    private static func progress(_ value: Double, _ goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
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
