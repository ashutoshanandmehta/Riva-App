import Foundation

/// In-memory data source that mirrors the design wireframe.
///
/// Values intentionally match the approved Figma frame (Sarah, 164.2 lbs,
/// Tirzepatide 12.5 mg, …) so the running app can be compared 1:1 against
/// design. Replace with `APIHomeRepository` once the backend exists.
struct MockHomeRepository: HomeRepository {

    func homeSnapshot() async throws -> HomeSnapshot {
        // Simulate a short network round-trip so loading states stay honest.
        try await Task.sleep(for: .milliseconds(250))
        return Self.snapshot()
    }

    // MARK: - Fixture

    /// Also used directly by SwiftUI previews (no async hop needed there).
    static func snapshot(now: Date = .now) -> HomeSnapshot {
        HomeSnapshot(
            user: UserProfile(firstName: "Sarah"),
            quote: "Consistency is your superpower.",
            weight: MockTrackerRepository.dashboard().weight,
            medicationLevel: MedicationLevelEstimate(
                currentMg: 1.8,
                peakMg: 4.0,
                explanation: "Modelled from your dose history — solid is past, dashed projects the days ahead."
            ),
            nextShot: ScheduledShot(
                drugName: "Tirzepatide",
                doseMg: 12.5,
                date: nextShotDate(from: now),
                suggestedSite: "Left arm",
                cycleDays: 7
            ),
            nutrients: [
                NutrientProgress(title: "Calories", value: 1450, goal: 2000, unit: " kcal"),
                NutrientProgress(title: "Protein", value: 95, goal: 110, unit: "g"),
                NutrientProgress(title: "Carbs", value: 104, goal: 150, unit: "g"),
                NutrientProgress(title: "Fiber", value: 18, goal: 28, unit: "g"),
            ],
            week: week(now: now),
            streakDays: 12,
            weightTodayLbs: 164.2,
            goal: WeightGoalProgress(currentLbs: 164.2, targetLbs: 145, progress: 0.65)
        )
    }

    /// Every day up to today logged, the rest of the week still open — the
    /// wireframe's week strip.
    private static func week(now: Date) -> [HomeDayStatus] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2  // Monday
        let today = calendar.startOfDay(for: now)
        let daysFromMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return (0..<7).map { offset in
            HomeDayStatus(
                dayKey: "week-day-\(offset)",
                letter: letters[offset],
                isToday: offset == daysFromMonday,
                isLogged: offset < daysFromMonday
            )
        }
    }

    /// Two days out at 9:54 PM — keeps the "2d left" ring of the wireframe true
    /// relative to whatever "today" is.
    private static func nextShotDate(from now: Date) -> Date {
        let calendar = Calendar.current
        let inTwoDays = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        return calendar.date(bySettingHour: 21, minute: 54, second: 0, of: inTwoDays) ?? inTwoDays
    }
}
