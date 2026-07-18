import Foundation

/// Aggregate payload backing the Home dashboard — one fetch, one render.
struct HomeSnapshot: Equatable, Sendable {
    var user: UserProfile
    /// Motivational strapline under the greeting.
    var quote: String
    var weight: WeightSummary
    var medicationLevel: MedicationLevelEstimate
    var nextShot: ScheduledShot
    var insight: RivaInsight
    var nutrients: [NutrientProgress]
}
