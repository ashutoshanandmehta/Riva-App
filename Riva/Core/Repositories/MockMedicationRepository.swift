import Foundation

/// In-memory data source for the Medication tab, mirroring the approved
/// wireframe (weekly Sunday 8:00 AM Semaglutide schedule, Level 2 at 0.5 mg).
///
/// Dates are generated relative to "now" so countdowns, the concentration
/// curve, and history stay truthful whenever the app runs.
struct MockMedicationRepository: MedicationRepository {

    func medicationDashboard() async throws -> MedicationDashboard {
        // Simulate a short network round-trip so loading states stay honest.
        try await Task.sleep(for: .milliseconds(250))
        return Self.dashboard()
    }

    // MARK: - Fixture

    /// Also used directly by SwiftUI previews.
    static func dashboard(now: Date = .now) -> MedicationDashboard {
        let doseMg = 0.5
        let nextDose = nextInjection(after: now)
        let pastDoses = pastInjections(before: nextDose, count: 4)

        return MedicationDashboard(
            drugName: "Semaglutide",
            titration: DoseTitration(
                level: 2,
                weeksCompleted: 4,
                weeksPerLevel: 4,
                currentDoseMg: doseMg
            ),
            nextDose: ScheduledShot(
                drugName: "Semaglutide",
                doseMg: doseMg,
                date: nextDose,
                suggestedSite: "Left Abdomen",
                cycleDays: 7
            ),
            curve: curve(now: now, doses: pastDoses, doseMg: doseMg),
            insight: RivaInsight(
                message: "GLP-1 concentration is currently peaking. You may feel reduced appetite today."
            ),
            history: pastDoses.enumerated().map { index, date in
                DoseRecord(
                    week: pastDoses.count - index,
                    doseMg: doseMg,
                    date: date,
                    site: injectionSites[index % injectionSites.count]
                )
            }
        )
    }

    /// Rotation pattern shown in history, most recent first.
    private static let injectionSites = ["Left Thigh", "Right Abdomen", "Right Thigh", "Left Abdomen"]

    /// Next Sunday 8:00 AM after `now`.
    private static func nextInjection(after now: Date) -> Date {
        let components = DateComponents(hour: 8, minute: 0, weekday: 1) // Sunday
        return Calendar.current.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(72 * 3600)
    }

    /// The `count` weekly injections preceding `nextDose`, most recent first.
    private static func pastInjections(before nextDose: Date, count: Int) -> [Date] {
        let calendar = Calendar.current
        return (1...count).compactMap {
            calendar.date(byAdding: .day, value: -7 * $0, to: nextDose)
        }
    }

    // MARK: Concentration model

    /// Samples a simple pharmacokinetic superposition across the current
    /// Mon–Sun week: each past dose contributes a response that ramps to a
    /// peak ~48h post-injection and decays over the following days.
    private static func curve(now: Date, doses: [Date], doseMg: Double) -> MedicationCurve {
        let weekStart = mostRecentMonday(onOrBefore: now)
        let sampleStepHours = 3.0
        let hoursInWeek = 7.0 * 24.0

        let points = stride(from: 0.0, through: hoursInWeek, by: sampleStepHours).map { offset in
            let sampleDate = weekStart.addingTimeInterval(offset * 3600)
            return MedicationCurvePoint(
                date: sampleDate,
                level: concentration(at: sampleDate, doses: doses, doseMg: doseMg)
            )
        }

        return MedicationCurve(
            points: points,
            therapeuticThreshold: 0.45 * doseMg
        )
    }

    private static func concentration(at date: Date, doses: [Date], doseMg: Double) -> Double {
        doses.reduce(0) { total, dose in
            total + doseMg * doseResponse(hoursSinceDose: date.timeIntervalSince(dose) / 3600)
        }
    }

    /// Normalized single-dose response: 0 before injection, peak ≈ 1 at 48h,
    /// smooth decay afterwards.
    private static func doseResponse(hoursSinceDose h: Double) -> Double {
        guard h > 0 else { return 0 }
        let peakHours = 48.0
        let shape = 1.4
        return pow(h / peakHours, shape) * exp(shape * (1 - h / peakHours))
    }

    private static func mostRecentMonday(onOrBefore date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }
}
