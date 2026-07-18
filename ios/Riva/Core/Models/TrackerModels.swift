import Foundation

/// Short-window weight trend for the Tracker tab (distinct from Home's
/// month-long `WeightSummary`).
struct WeightTrend: Equatable, Sendable {
    var currentLbs: Double
    /// Change over the trailing 7 days; negative = loss.
    var weeklyChangeLbs: Double
    /// Daily weights for the trailing week, oldest first (drives the bars).
    var recentDailyLbs: [Double]
}

/// Daily hydration progress.
struct HydrationStatus: Equatable, Sendable {
    var glasses: Int
    var goalGlasses: Int

    /// Fill fraction in `0...1`.
    var progress: Double {
        guard goalGlasses > 0 else { return 0 }
        return min(max(Double(glasses) / Double(goalGlasses), 0), 1)
    }
}

/// Daily protein progress.
struct ProteinStatus: Equatable, Sendable {
    var grams: Double
    var goalGrams: Double

    var progress: Double {
        guard goalGrams > 0 else { return 0 }
        return min(max(grams / goalGrams, 0), 1)
    }

    var gramsRemaining: Double { max(goalGrams - grams, 0) }
}

/// The patient's currently reported side effect.
struct SideEffectReport: Equatable, Sendable {
    enum Severity: Equatable, Sendable {
        case none
        case mild
        case moderate
        case severe
    }

    /// e.g. "Mild Nausea".
    var summary: String
    var severity: Severity
}

/// Last night's sleep, plus a week of history for the mini chart.
struct SleepStatus: Equatable, Sendable {
    /// Last night's duration in minutes (440 = 7h 20m).
    var durationMinutes: Int
    /// Sleep efficiency in `0...1`.
    var efficiency: Double
    /// Relative durations for the trailing nights, oldest first, each `0...1`.
    var recentNights: [Double]
}

/// Generic value-vs-goal pair (calories, protein, …).
struct QuantityGoal: Equatable, Sendable {
    var value: Double
    var goal: Double

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }
}

/// Week-scoped weight progress for the summary screen.
struct WeeklyWeightProgress: Equatable, Sendable {
    /// Change across the week; negative = loss.
    var changeLbs: Double
    /// Whether the patient is pacing toward their goal.
    var isOnTrack: Bool
    /// Daily weights across the week, oldest first (drives the bars).
    var dailyLbs: [Double]
    var totalLostLbs: Double
    var goalLbs: Double
}

/// A named coaching note (e.g. from "Remi", Riva's AI coach) with Markdown
/// emphasis.
struct CoachNote: Equatable, Sendable {
    var coachName: String
    var message: String
}

/// Aggregate payload backing the Weekly Summary screen.
struct WeeklySummary: Equatable, Sendable {
    var interval: DateInterval
    var weight: WeeklyWeightProgress
    var coachNote: CoachNote
    var lastDoseDate: Date
    var nextDoseDate: Date
    /// kcal per day.
    var calories: QuantityGoal
    /// grams per day.
    var protein: QuantityGoal
    var hydrationLitersPerDay: Double
    var sleepAverageMinutes: Int
}

/// Aggregate payload backing the Tracker tab.
struct TrackerDashboard: Equatable, Sendable {
    /// Markdown-formatted coaching message ("Tomorrow is **injection day**…").
    var intelligence: RivaInsight
    var weight: WeightTrend
    var hydration: HydrationStatus
    var protein: ProteinStatus
    var sideEffect: SideEffectReport
    var sleep: SleepStatus
}
