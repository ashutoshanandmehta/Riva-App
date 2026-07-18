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
            weight: WeightSummary(
                history: weightHistory(endingAt: now),
                currentLbs: 164.2,
                targetLbs: 145,
                weeklyChangeLbs: -1.2,
                totalChangeLbs: -18.4,
                goalProgress: 0.65
            ),
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
            insight: RivaInsight(
                message: "Your nausea usually occurs after low protein meals. Riva suggests adding 15g of protein to your breakfast."
            ),
            nutrients: [
                NutrientProgress(title: "Protein", valueText: "95g", targetText: "of 110g", progress: 95.0 / 110.0),
                NutrientProgress(title: "Water", valueText: "6", targetText: "of 8 glasses", progress: 6.0 / 8.0),
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

    /// Deterministic month of gently declining weight (182.6 → 164.2 lbs).
    /// A fixed sine wiggle keeps the curve organic without run-to-run jitter.
    private static func weightHistory(endingAt now: Date) -> [WeightPoint] {
        let calendar = Calendar.current
        let startLbs = 182.6
        let endLbs = 164.2
        let dayCount = 28

        return (0...dayCount).map { offset in
            let t = Double(offset) / Double(dayCount)
            let base = startLbs + (endLbs - startLbs) * t
            // Wiggle fades to zero at the last point so "today" lands exactly
            // on the headline 164.2.
            let wiggle = sin(t * .pi * 3.2) * 0.9 * (1 - t)
            let date = calendar.date(byAdding: .day, value: offset - dayCount, to: now) ?? now
            return WeightPoint(date: date, weightLbs: base + wiggle)
        }
    }
}
