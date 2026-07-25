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

    /// Adds water ounces to today's hydration total, same manual-entry path
    /// as `logProtein`.
    func logWater(ounces: Int) async throws -> DayTotals

    /// Adds calories to today's nutrition totals, same manual-entry path as
    /// `logProtein`.
    func logCalories(kcal: Int) async throws -> DayTotals

    /// Replaces today's set of side effects.
    func logSideEffects(_ entries: [SideEffectEntry]) async throws -> SideEffectsLogResult

    /// Answers today's sleep quality check-in question.
    func logSleep(optionCode: String) async throws -> CheckinLogResult

    /// Records a completed wellness practice session.
    func logWellnessSession(
        practiceId: String,
        kind: WellnessKind,
        minutes: Int
    ) async throws -> WellnessLogResult
}
