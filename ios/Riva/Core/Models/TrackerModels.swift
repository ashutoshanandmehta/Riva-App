import Foundation

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

/// Daily calorie progress.
struct CalorieStatus: Equatable, Sendable {
    var calories: Int
    var goalCalories: Int

    var progress: Double {
        guard goalCalories > 0 else { return 0 }
        return min(max(Double(calories) / Double(goalCalories), 0), 1)
    }

    var caloriesRemaining: Int { max(goalCalories - calories, 0) }
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

/// A coaching note with Markdown emphasis.
struct CoachNote: Equatable, Sendable {
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
    /// Month-long trend, deltas, and goal progress — the Tracker tab leads
    /// with the full `WeightTrackingCard`.
    var weight: WeightSummary
    var hydration: HydrationStatus
    var protein: ProteinStatus
    var calorie: CalorieStatus
    var sideEffect: SideEffectReport
    var sleep: SleepStatus
}
