import Foundation

/// One point on the weight trend chart.
struct WeightPoint: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let weightLbs: Double
}

/// Journey progress toward a target weight.
///
/// Nil wherever the user has not set a goal — the UI hides the block rather
/// than inventing a target from the current weight.
struct WeightGoalProgress: Equatable, Sendable {
    var currentLbs: Double
    var targetLbs: Double
    /// Overall completion in `0...1`, measured from the starting weight.
    var progress: Double

    var lbsToGo: Double { max(currentLbs - targetLbs, 0) }
}

/// Everything the Weight Tracking card needs.
struct WeightSummary: Equatable, Sendable {
    /// Trailing history window (the past month), oldest first.
    var history: [WeightPoint]
    var currentLbs: Double
    /// Change over the trailing 7 days; negative = loss.
    var weeklyChangeLbs: Double
    /// Change since the journey started; negative = loss. Measured against the
    /// full history, not the charted window.
    var totalChangeLbs: Double
    /// Nil until the user sets a goal weight.
    var goal: WeightGoalProgress?
}
