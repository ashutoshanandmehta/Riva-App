import Foundation

/// Aggregate payload backing the Home dashboard — one fetch, one render.
struct HomeSnapshot: Equatable, Sendable {
    var user: UserProfile
    /// Motivational strapline under the greeting.
    var quote: String
    // Weight moved to the Tracker tab (`TrackerDashboard.weight`), so Home no
    // longer carries a month of WeightPoints it never renders.
    var medicationLevel: MedicationLevelEstimate
    var nextShot: ScheduledShot
    var nutrients: [NutrientProgress]
}
