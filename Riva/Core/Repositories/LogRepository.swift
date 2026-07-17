import Foundation

/// Quick-log writes: weight, shots, protein, side effects, and sleep.
/// All persistence is server-authoritative through the Riva backend.
protocol LogRepository: Sendable {
    func logWeight(pounds: Double) async throws -> WeightLogResult

    func logShot(
        medicationName: String,
        doseMg: Double,
        site: InjectionSite,
        comfortRating: Int?
    ) async throws -> ShotLogResult

    /// Adds protein grams to today's nutrition totals (a manual
    /// `food_entries` row plus the daily increment, like an accepted scan).
    func logProtein(grams: Int) async throws -> DayTotals

    /// Replaces today's set of side effects.
    func logSideEffects(_ entries: [SideEffectEntry]) async throws -> SideEffectsLogResult

    /// Answers today's sleep quality check-in question.
    func logSleep(optionCode: String) async throws -> CheckinLogResult
}
