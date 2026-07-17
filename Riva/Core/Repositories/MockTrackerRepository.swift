import Foundation

/// In-memory data source for the Tracker tab, mirroring the approved
/// wireframe (184.2 lbs, 6/8 glasses, 85g protein, mild nausea, 7h 20m).
struct MockTrackerRepository: TrackerRepository {

    func trackerDashboard() async throws -> TrackerDashboard {
        // Simulate a short network round-trip so loading states stay honest.
        try await Task.sleep(for: .milliseconds(250))
        return Self.dashboard()
    }

    func weeklySummary() async throws -> WeeklySummary {
        try await Task.sleep(for: .milliseconds(250))
        return Self.summary()
    }

    // MARK: - Fixture

    /// Also used directly by SwiftUI previews.
    static func dashboard() -> TrackerDashboard {
        TrackerDashboard(
            intelligence: RivaInsight(
                message: "Tomorrow is **injection day**. Hydrate extra today to minimize potential side effects!"
            ),
            weight: WeightTrend(
                currentLbs: 184.2,
                weeklyChangeLbs: -0.8,
                recentDailyLbs: [185.0, 184.9, 184.8, 184.7, 184.5, 184.3, 184.2]
            ),
            hydration: HydrationStatus(glasses: 6, goalGlasses: 8),
            protein: ProteinStatus(grams: 85, goalGrams: 110),
            sideEffect: SideEffectReport(summary: "Mild Nausea", severity: .mild),
            sleep: SleepStatus(
                durationMinutes: 440, // 7h 20m
                efficiency: 0.92,
                recentNights: [0.45, 0.35, 0.62, 1.0, 0.7, 0.4, 0.82]
            )
        )
    }

    /// Weekly summary fixture — interval and dose dates are derived from
    /// "now" so the screen stays truthful whenever the app runs.
    static func summary(now: Date = .now) -> WeeklySummary {
        let calendar = Calendar.current
        let weekStart = mostRecentMonday(onOrBefore: now)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        let nextDose = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 8, minute: 0, weekday: 1), // Sunday
            matchingPolicy: .nextTime
        ) ?? now
        let lastDose = calendar.date(byAdding: .day, value: -7, to: nextDose) ?? now

        return WeeklySummary(
            interval: DateInterval(start: weekStart, end: weekEnd),
            weight: WeeklyWeightProgress(
                changeLbs: -1.2,
                isOnTrack: true,
                dailyLbs: [185.4, 185.8, 185.1, 185.3, 184.9, 185.0, 184.2],
                totalLostLbs: 8.4,
                goalLbs: 175
            ),
            coachNote: CoachNote(
                coachName: "Remi",
                message: "Your protein intake was **15% higher** this week, which is great for muscle preservation! Keep focusing on your morning habits; consistency there is driving your progress."
            ),
            lastDoseDate: lastDose,
            nextDoseDate: nextDose,
            calories: QuantityGoal(value: 1640, goal: 1800),
            protein: QuantityGoal(value: 115, goal: 120),
            hydrationLitersPerDay: 2.4,
            sleepAverageMinutes: 462 // 7h 42m
        )
    }

    private static func mostRecentMonday(onOrBefore date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }
}
