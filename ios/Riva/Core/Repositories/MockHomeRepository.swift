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
                NutrientProgress(title: "Protein", valueText: "95g", targetText: "of 110g", progress: 95.0 / 110.0),
                NutrientProgress(title: "Water", valueText: "6", targetText: "of 8 glasses", progress: 6.0 / 8.0),
                NutrientProgress(title: "Calories", valueText: "1450", targetText: "of 2000 kcal", progress: 1450.0 / 2000.0),
            ]
        )
    }

    /// Two days out at 9:54 PM — keeps the "2d left" ring of the wireframe true
    /// relative to whatever "today" is.
    private static func nextShotDate(from now: Date) -> Date {
        let calendar = Calendar.current
        let inTwoDays = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        return calendar.date(bySettingHour: 21, minute: 54, second: 0, of: inTwoDays) ?? inTwoDays
    }
}
