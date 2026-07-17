import Foundation

/// In-memory data source for the Profile screen, mirroring the approved
/// wireframe (Sarah Mitchell, 164.2 → 145 lbs, Tirzepatide 12.5 mg).
struct MockProfileRepository: ProfileRepository {

    func profile() async throws -> ProfileSnapshot {
        // Simulate a short network round-trip so loading states stay honest.
        try await Task.sleep(for: .milliseconds(200))
        return Self.snapshot()
    }

    // MARK: - Fixture

    /// Also used directly by SwiftUI previews.
    static func snapshot() -> ProfileSnapshot {
        ProfileSnapshot(
            fullName: "Sarah Mitchell",
            email: "sarah.mitchell@icloud.com",
            goals: PersonalGoals(currentWeightLbs: 164.2, goalWeightLbs: 145.0),
            calories: QuantityGoal(value: 1440, goal: 1850),
            protein: QuantityGoal(value: 48, goal: 120),
            medication: MedicationSettings(
                drugName: "Tirzepatide",
                currentDoseMg: 12.5,
                injectionDaySummary: "Every Sunday Morning",
                currentSite: "Abdomen (Left)"
            )
        )
    }
}
