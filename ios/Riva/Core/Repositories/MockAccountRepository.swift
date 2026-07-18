import Foundation

/// Canned account data for previews and UI work without the network.
struct MockAccountRepository: AccountRepository {

    static let sampleBundle = AccountBundle(
        profile: AccountProfile(
            name: "Sarah",
            dateOfBirth: "1990-04-12",
            gender: "female",
            clinicianName: "Dr. Chen",
            startWeight: 192,
            goalWeight: 158,
            heightInches: 65,
            timezone: "America/Los_Angeles"
        ),
        nutritionGoals: NutritionGoals(
            proteinGoal: 100, carbGoal: 150, fiberGoal: 28, waterGoal: 64
        ),
        healthGoals: HealthGoalFlags(
            glp1Support: true,
            weightMgmt: true,
            nutritionDiet: true,
            musclePreserve: false,
            exerciseMove: false,
            sleepRecovery: true
        ),
        plan: MedicationPlan(
            name: "Semaglutide",
            currentDoseMg: 0.5,
            cadenceDays: 7,
            doseFrequency: "weekly",
            reminderDescription: "Saturday mornings",
            startDate: "2026-05-02"
        )
    )

    func me() async throws -> AccountBundle {
        try? await Task.sleep(for: .milliseconds(400))
        return Self.sampleBundle
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> AccountProfile {
        try? await Task.sleep(for: .milliseconds(400))
        let current = Self.sampleBundle.profile
        return AccountProfile(
            name: update.name ?? current.name,
            dateOfBirth: update.dateOfBirth ?? current.dateOfBirth,
            gender: update.gender ?? current.gender,
            clinicianName: update.clinicianName ?? current.clinicianName,
            startWeight: update.startWeight ?? current.startWeight,
            goalWeight: update.goalWeight ?? current.goalWeight,
            heightInches: update.heightInches ?? current.heightInches,
            timezone: update.timezone ?? current.timezone
        )
    }

    func updateGoals(_ update: GoalsUpdate) async throws -> NutritionGoals {
        try? await Task.sleep(for: .milliseconds(400))
        let current = Self.sampleBundle.nutritionGoals
        return NutritionGoals(
            proteinGoal: update.proteinGoal ?? current.proteinGoal,
            carbGoal: update.carbGoal ?? current.carbGoal,
            fiberGoal: update.fiberGoal ?? current.fiberGoal,
            waterGoal: update.waterGoal ?? current.waterGoal
        )
    }

    func updatePlan(_ update: PlanUpdate) async throws -> MedicationPlan {
        try? await Task.sleep(for: .milliseconds(400))
        let current = Self.sampleBundle.plan!
        return MedicationPlan(
            name: update.name ?? current.name,
            currentDoseMg: update.currentDoseMg ?? current.currentDoseMg,
            cadenceDays: update.cadenceDays ?? current.cadenceDays,
            doseFrequency: current.doseFrequency,
            reminderDescription: update.reminderDescription ?? current.reminderDescription,
            startDate: current.startDate
        )
    }

    func weights() async throws -> [WeightEntry] {
        try? await Task.sleep(for: .milliseconds(400))
        return [
            WeightEntry(
                id: "w3", pounds: 184.2, doseMg: 0.5, measuredAt: "2026-07-17T08:05:00Z"
            ),
            WeightEntry(
                id: "w2", pounds: 185.0, doseMg: 0.5, measuredAt: "2026-07-14T08:12:00Z"
            ),
            WeightEntry(
                id: "w1", pounds: 186.4, doseMg: 0.25, measuredAt: "2026-07-10T07:58:00Z"
            ),
        ]
    }

    func shots() async throws -> [ShotEntry] {
        try? await Task.sleep(for: .milliseconds(400))
        return [
            ShotEntry(
                id: "s2", medicationName: "Semaglutide", doseMg: 0.5,
                takenAt: "2026-07-12T09:00:00Z", injectionSite: "left_thigh",
                comfortRating: 4
            ),
            ShotEntry(
                id: "s1", medicationName: "Semaglutide", doseMg: 0.5,
                takenAt: "2026-07-05T09:10:00Z", injectionSite: "lower_left_abs",
                comfortRating: 3
            ),
        ]
    }

    func sideEffects() async throws -> [SideEffectDayLog] {
        try? await Task.sleep(for: .milliseconds(400))
        return [
            SideEffectDayLog(
                logDate: "2026-07-13",
                note: "Mild queasiness the morning after the shot.",
                effects: [
                    SideEffectEntry(effect: "nausea", severity: 2),
                    SideEffectEntry(effect: "fatigue", severity: 1),
                ]
            ),
        ]
    }

    func exportData() async throws -> Data {
        try? await Task.sleep(for: .milliseconds(400))
        return Data(#"{"profile": {"name": "Sarah"}}"#.utf8)
    }

    func deleteAccount() async throws {
        try? await Task.sleep(for: .milliseconds(400))
    }
}
