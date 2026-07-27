import Foundation

/// Aggregate payload backing the Home dashboard — one fetch, one render.
struct HomeSnapshot: Equatable, Sendable {
    var user: UserProfile
    /// Motivational strapline under the greeting.
    var quote: String
    /// The same month of weigh-ins the Tracker charts. Home shows the trend
    /// under today's calories; the Tracker keeps it too, and remains the way
    /// through to the full history.
    var weight: WeightSummary
    var medicationLevel: MedicationLevelEstimate
    var nextShot: ScheduledShot
    var nutrients: [NutrientProgress]
    /// This week's activity, Monday first — backs the week strip.
    var week: [HomeDayStatus]
    /// Consecutive days with nutrition logged, ending today or yesterday. Zero
    /// hides the streak chip rather than showing "0d".
    var streakDays: Int
    /// Today's latest weigh-in in the user's timezone, nil when they haven't
    /// weighed in today. Never a stand-in from an earlier day.
    var weightTodayLbs: Double?
    /// Journey progress toward the target weight — the figures only, not the
    /// history behind them. Nil until the user sets a goal weight, in which
    /// case Home omits the card entirely.
    var goal: WeightGoalProgress?
}

/// One cell of Home's week strip.
///
/// `isLogged` comes from real nutrition activity, never from the calendar — a
/// day that has passed without a log must not read as completed.
struct HomeDayStatus: Identifiable, Equatable, Sendable {
    /// `yyyy-MM-dd` in the user's profile timezone; also the identity.
    var id: String { dayKey }
    var dayKey: String
    /// Single-letter weekday label, e.g. "M".
    var letter: String
    var isToday: Bool
    var isLogged: Bool
}
