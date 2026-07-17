import Foundation

/// One logged body-weight measurement.
struct WeightEntry: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let weightLbs: Double
}

/// Everything the Weight Tracking card needs.
struct WeightSummary: Equatable, Sendable {
    /// Trailing history window (typically the past month), oldest first.
    var history: [WeightEntry]
    var currentLbs: Double
    var targetLbs: Double
    /// Change over the trailing 7 days; negative = loss.
    var weeklyChangeLbs: Double
    /// Change since the journey started; negative = loss.
    var totalChangeLbs: Double
    /// Overall goal completion in `0...1` (as computed by the backend).
    var goalProgress: Double

    var lbsToGo: Double { max(currentLbs - targetLbs, 0) }
}
