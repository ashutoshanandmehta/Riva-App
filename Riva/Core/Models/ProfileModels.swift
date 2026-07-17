import Foundation

/// Weight goals shown under "Personal Goals".
struct PersonalGoals: Equatable, Sendable {
    var currentWeightLbs: Double
    var goalWeightLbs: Double
}

/// One medication-related setting row.
struct MedicationSettings: Equatable, Sendable {
    var drugName: String
    var currentDoseMg: Double
    /// e.g. "Every Sunday Morning".
    var injectionDaySummary: String
    /// e.g. "Abdomen (Left)".
    var currentSite: String
}

/// Aggregate payload backing the Profile screen.
struct ProfileSnapshot: Equatable, Sendable {
    var fullName: String
    var email: String
    var goals: PersonalGoals
    /// Daily calorie target with today's progress.
    var calories: QuantityGoal
    /// Daily protein target with today's progress.
    var protein: QuantityGoal
    var medication: MedicationSettings

    /// "SM" — initials for the avatar fallback.
    var initials: String {
        fullName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
    }
}
