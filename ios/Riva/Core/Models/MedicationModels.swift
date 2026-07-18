import Foundation

/// Pharmacokinetic estimate of active drug currently in the patient's system.
struct MedicationLevelEstimate: Equatable, Sendable {
    /// Estimated active amount right now, in mg.
    var currentMg: Double
    /// Model's peak reference level, in mg — used to scale the gauge.
    var peakMg: Double
    /// Plain-language explanation of how the estimate is derived.
    var explanation: String

    /// Gauge fill in `0...1`.
    var gaugeFraction: Double {
        guard peakMg > 0 else { return 0 }
        return min(max(currentMg / peakMg, 0), 1)
    }
}

/// Where the patient is in their dose-escalation (titration) plan.
struct DoseTitration: Equatable, Sendable {
    /// Current escalation step (e.g. "Level 2").
    var level: Int
    /// Weeks completed at this level.
    var weeksCompleted: Int
    /// Weeks required before stepping up to the next level.
    var weeksPerLevel: Int
    /// Dose currently prescribed, in mg.
    var currentDoseMg: Double

    /// Ring fill in `0...1`.
    var progress: Double {
        guard weeksPerLevel > 0 else { return 0 }
        return min(max(Double(weeksCompleted) / Double(weeksPerLevel), 0), 1)
    }
}

/// One sample of the modelled GLP-1 concentration curve.
struct MedicationCurvePoint: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    /// Modelled concentration (relative units scaled to dose mg).
    let level: Double
}

/// The modelled concentration curve for the current week.
struct MedicationCurve: Equatable, Sendable {
    /// Samples across the current week (Mon–Sun), oldest first.
    var points: [MedicationCurvePoint]
    /// Concentration above which the patient typically feels effects —
    /// rendered as the dotted reference line.
    var therapeuticThreshold: Double

    /// The sample closest to `now` (drives the "you are here" marker).
    func point(closestTo now: Date = .now) -> MedicationCurvePoint? {
        points.min { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) }
    }
}

/// A past injection, as shown in Dose History.
struct DoseRecord: Identifiable, Equatable, Sendable {
    var id: Date { date }
    /// Week number within the program (1 = first shot).
    var week: Int
    var doseMg: Double
    var date: Date
    /// Injection site used, e.g. "Left Thigh".
    var site: String
}

/// Aggregate payload backing the Medication tab.
struct MedicationDashboard: Equatable, Sendable {
    var drugName: String
    var titration: DoseTitration
    var nextDose: ScheduledShot
    var curve: MedicationCurve
    /// Coaching note shown under the curve.
    var insight: RivaInsight
    /// Past injections, most recent first.
    var history: [DoseRecord]
}

/// The next scheduled injection.
struct ScheduledShot: Equatable, Sendable {
    var drugName: String
    var doseMg: Double
    var date: Date
    var suggestedSite: String
    /// Dosing interval in days (weekly GLP-1 schedules = 7).
    var cycleDays: Int

    /// Whole days remaining until the shot, never negative.
    func daysRemaining(from now: Date = .now) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return max(days, 0)
    }

    /// How far through the current dosing cycle the patient is, in `0...1`.
    func cycleProgress(from now: Date = .now) -> Double {
        guard cycleDays > 0 else { return 0 }
        let elapsed = Double(cycleDays - daysRemaining(from: now))
        return min(max(elapsed / Double(cycleDays), 0), 1)
    }
}
