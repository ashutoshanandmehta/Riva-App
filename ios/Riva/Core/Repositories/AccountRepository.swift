import Foundation

/// Account data: profile, goals, medication plan, history reads, export,
/// and deletion. UI code depends only on this protocol.
protocol AccountRepository: Sendable {
    /// Profile, goals, and active plan in one call.
    func me() async throws -> AccountBundle

    /// Sends only the fields set on the update; returns the full profile.
    func updateProfile(_ update: ProfileUpdate) async throws -> AccountProfile

    func updateGoals(_ update: GoalsUpdate) async throws -> NutritionGoals

    /// Updates the active plan, creating one server-side if none exists.
    func updatePlan(_ update: PlanUpdate) async throws -> MedicationPlan

    /// Recent weight entries, newest first.
    func weights() async throws -> [WeightEntry]

    /// Recent shots, newest first.
    func shots() async throws -> [ShotEntry]

    /// Recent daily side-effect logs, newest first.
    func sideEffects() async throws -> [SideEffectDayLog]

    /// The user's full data dump as raw JSON, ready to share or save.
    func exportData() async throws -> Data

    /// Permanently deletes the account and all its data.
    func deleteAccount() async throws
}
