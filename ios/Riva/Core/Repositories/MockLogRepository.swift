import Foundation

/// Canned quick-log repository for previews.
struct MockLogRepository: LogRepository {

    func logWeight(pounds: Double) async throws -> WeightLogResult {
        try? await Task.sleep(for: .milliseconds(400))
        return WeightLogResult(
            weightId: "preview", pounds: pounds, doseMg: 0.5, measuredAt: "2026-07-17T12:00:00Z"
        )
    }

    func logShot(
        medicationName: String,
        doseMg: Double,
        site: InjectionSite,
        comfortRating: Int?
    ) async throws -> ShotLogResult {
        try? await Task.sleep(for: .milliseconds(400))
        return ShotLogResult(
            shotId: "preview", medicationName: medicationName, doseMg: doseMg,
            takenAt: "2026-07-17T12:00:00Z", injectionSite: site.rawValue
        )
    }

    func logProtein(grams: Int) async throws -> DayTotals {
        try? await Task.sleep(for: .milliseconds(400))
        return DayTotals(
            day: "2026-07-17", calories: 820, proteinGrams: 41 + grams,
            carbGrams: 88, fiberGrams: 12, waterOunces: 24
        )
    }

    func logSideEffects(_ entries: [SideEffectEntry]) async throws -> SideEffectsLogResult {
        try? await Task.sleep(for: .milliseconds(400))
        return SideEffectsLogResult(logDate: "2026-07-17", effects: entries)
    }

    func logSleep(optionCode: String) async throws -> CheckinLogResult {
        try? await Task.sleep(for: .milliseconds(400))
        let option = SleepOption.all.first { $0.code == optionCode } ?? SleepOption.all[1]
        return CheckinLogResult(
            checkinDate: "2026-07-17", questionId: "sleep",
            optionCode: option.code, label: option.label, value: 4
        )
    }
}
