import Foundation

/// Live dashboard repositories: one aggregate fetch from the backend
/// (`GET /v1/dashboard`), mapped into each tab's display models. New
/// accounts with no logs get honest empty states, never sample numbers.

// MARK: - Wire payload

struct DashboardPayload: Codable, Sendable {
    struct SleepCheckin: Codable, Sendable {
        let checkinDate: String
        let value: Int
        let label: String
    }

    let profile: AccountProfile
    let nutritionGoals: NutritionGoals
    let plan: MedicationPlan?
    let today: DayTotals?
    let weekNutrition: [DayTotals]
    let weights: [WeightEntry]
    let shots: [ShotEntry]
    let sideEffectsToday: [SideEffectEntry]
    let sleepCheckins: [SleepCheckin]
}

// MARK: - Shared fetch + parsing

struct DashboardService: Sendable {

    private let baseURL: URL
    private let auth: any AuthRepository
    private let urlSession: URLSession

    init(auth: any AuthRepository, baseURL: URL = BackendEnvironment.scanServiceURL) {
        self.auth = auth
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        urlSession = URLSession(configuration: config)
    }

    func fetch() async throws -> DashboardPayload {
        guard let token = try await auth.validAccessToken() else {
            throw ScanServiceError.signInRequired
        }
        var request = URLRequest(url: baseURL.appending(path: "v1/dashboard"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ScanServiceError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw ScanServiceError.unreachable
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw ScanServiceError.signInRequired }
            throw ScanServiceError.service("Could not load your data. Try again.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DashboardPayload.self, from: data)
    }

    static func parseTimestamp(_ raw: String) -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: raw) { return date }
        return Date()
    }

    static func parseDay(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw) ?? Date()
    }
}

// MARK: - Mapping helpers

enum DashboardMapping {

    /// One-week GLP-1 half life: each logged dose decays by half every
    /// seven days. An educational model, not pharmacology.
    static func medicationLevel(shots: [ShotEntry], at moment: Date = .now) -> Double {
        shots.reduce(0) { total, shot in
            let taken = DashboardService.parseTimestamp(shot.takenAt)
            let days = moment.timeIntervalSince(taken) / 86_400
            guard days >= 0 else { return total }
            return total + shot.doseMg * pow(0.5, days / 7)
        }
    }

    static func weightSummary(_ payload: DashboardPayload) -> WeightSummary {
        let ordered = payload.weights.reversed()  // API is newest first
        var history = ordered.map {
            WeightPoint(date: DashboardService.parseTimestamp($0.measuredAt), weightLbs: $0.pounds)
        }
        let current = history.last?.weightLbs ?? payload.profile.startWeight ?? 0
        if history.isEmpty, current > 0 {
            // A single synthetic point keeps the chart axes stable.
            history = [WeightPoint(date: .now, weightLbs: current)]
        }
        let start = payload.profile.startWeight ?? history.first?.weightLbs ?? current
        let target = payload.profile.goalWeight ?? current
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let weekBase = history.last(where: { $0.date <= weekAgo })?.weightLbs
            ?? history.first?.weightLbs ?? current
        let progress: Double
        if start > target, start > 0 {
            progress = min(max((start - current) / (start - target), 0), 1)
        } else {
            progress = 0
        }
        return WeightSummary(
            history: history,
            currentLbs: current,
            targetLbs: target,
            weeklyChangeLbs: current - weekBase,
            totalChangeLbs: current - start,
            goalProgress: progress
        )
    }

    static func nextShot(_ payload: DashboardPayload) -> ScheduledShot {
        let cadence = payload.plan?.cadenceDays ?? 7
        let lastShotDate = payload.shots.first.map {
            DashboardService.parseTimestamp($0.takenAt)
        }
        let dueDate = lastShotDate?.addingTimeInterval(Double(cadence) * 86_400)
            ?? Date()
        return ScheduledShot(
            drugName: payload.plan?.name ?? "Your medication",
            doseMg: payload.plan?.currentDoseMg ?? 0,
            date: dueDate,
            suggestedSite: suggestedSite(shots: payload.shots),
            cycleDays: cadence
        )
    }

    static func suggestedSite(shots: [ShotEntry]) -> String {
        var lastUsed: [InjectionSite: Date] = [:]
        for shot in shots {
            guard let site = InjectionSite(rawValue: shot.injectionSite) else { continue }
            let taken = DashboardService.parseTimestamp(shot.takenAt)
            if (lastUsed[site] ?? .distantPast) < taken {
                lastUsed[site] = taken
            }
        }
        let pick = InjectionSite.allCases.min {
            (lastUsed[$0] ?? .distantPast) < (lastUsed[$1] ?? .distantPast)
        }
        return (pick ?? .lowerLeftAbs).title
    }

    static func sleepStatus(_ checkins: [DashboardPayload.SleepCheckin]) -> SleepStatus {
        let latest = checkins.first
        let nights = checkins.reversed().suffix(7).map { Double($0.value) / 5 }
        return SleepStatus(
            // Duration is unknown (we track quality); zero tells the card
            // to render the quality label instead.
            durationMinutes: 0,
            efficiency: latest.map { Double($0.value) / 5 } ?? 0,
            recentNights: Array(nights)
        )
    }

    static func sideEffectReport(_ effects: [SideEffectEntry]) -> SideEffectReport {
        guard let worst = effects.max(by: { $0.severity < $1.severity }) else {
            return SideEffectReport(summary: "None reported today", severity: .none)
        }
        let name = SideEffect(rawValue: worst.effect)?.title ?? worst.effect.capitalized
        let severity: SideEffectReport.Severity
        let word: String
        switch worst.severity {
        case ..<3: severity = .mild; word = "Mild"
        case 3: severity = .moderate; word = "Moderate"
        default: severity = .severe; word = "Severe"
        }
        return SideEffectReport(summary: "\(word) \(name)", severity: severity)
    }

    static func weekAverage(_ rows: [DayTotals], _ value: (DayTotals) -> Int) -> Double {
        guard !rows.isEmpty else { return 0 }
        return Double(rows.map(value).reduce(0, +)) / Double(rows.count)
    }
}

// MARK: - Home

struct APIHomeRepository: HomeRepository {

    private let service: DashboardService

    init(service: DashboardService) {
        self.service = service
    }

    func homeSnapshot() async throws -> HomeSnapshot {
        let payload = try await service.fetch()
        let weight = DashboardMapping.weightSummary(payload)
        let level = DashboardMapping.medicationLevel(shots: payload.shots)
        let planDose = payload.plan?.currentDoseMg ?? 0
        let goals = payload.nutritionGoals
        let today = payload.today

        let firstName = payload.profile.name
            .split(separator: " ").first.map(String.init) ?? "there"

        let insightMessage: String
        if payload.shots.isEmpty && payload.weights.isEmpty {
            insightMessage = "Welcome to Riva. Log your first shot and a weight, and this page starts working for you."
        } else if weight.totalChangeLbs < 0 {
            insightMessage = "You are down \(RivaFormat.weight(abs(weight.totalChangeLbs))) lbs so far. Steady weeks win."
        } else {
            insightMessage = "Keep logging meals and weights; trends need a little data to show themselves."
        }

        return HomeSnapshot(
            user: UserProfile(firstName: firstName == "there" ? "there" : firstName),
            quote: "Consistency is your superpower.",
            weight: weight,
            medicationLevel: MedicationLevelEstimate(
                currentMg: (level * 100).rounded() / 100,
                peakMg: max(planDose * 2, level, 0.5),
                explanation: payload.shots.isEmpty
                    ? "Log your first shot and Riva estimates the medication in your system through the week."
                    : "Estimated from your logged shots with a one week half life. Solid is past, dashed projects ahead."
            ),
            nextShot: DashboardMapping.nextShot(payload),
            insight: RivaInsight(message: insightMessage),
            nutrients: [
                NutrientProgress(
                    title: "Protein",
                    valueText: "\(today?.proteinGrams ?? 0)g",
                    targetText: "of \(goals.proteinGoal)g",
                    progress: progress(today?.proteinGrams, goals.proteinGoal)
                ),
                NutrientProgress(
                    title: "Water",
                    valueText: "\((today?.waterOunces ?? 0) / 8)",
                    targetText: "of \(max(goals.waterGoal / 8, 1)) glasses",
                    progress: progress(today?.waterOunces, goals.waterGoal)
                ),
                NutrientProgress(
                    title: "Carbs",
                    valueText: "\(today?.carbGrams ?? 0)g",
                    targetText: "of \(goals.carbGoal)g",
                    progress: progress(today?.carbGrams, goals.carbGoal)
                ),
                NutrientProgress(
                    title: "Fiber",
                    valueText: "\(today?.fiberGrams ?? 0)g",
                    targetText: "of \(goals.fiberGoal)g",
                    progress: progress(today?.fiberGrams, goals.fiberGoal)
                ),
            ]
        )
    }

    private func progress(_ value: Int?, _ goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(Double(value ?? 0) / Double(goal), 0), 1)
    }
}

// MARK: - Medication

struct APIMedicationRepository: MedicationRepository {

    private let service: DashboardService

    init(service: DashboardService) {
        self.service = service
    }

    func medicationDashboard() async throws -> MedicationDashboard {
        let payload = try await service.fetch()
        let planDose = payload.plan?.currentDoseMg ?? 0.5
        let ordered = payload.shots.reversed()  // oldest first

        // Titration: how many distinct dose steps so far, and weeks at the
        // current one (4-week steps are the typical escalation rhythm).
        let doses = ordered.map(\.doseMg)
        let level = max(Set(doses).count, 1)
        var weeksAtCurrent = 0
        if let firstAtCurrent = ordered.first(where: { $0.doseMg == planDose }) {
            let start = DashboardService.parseTimestamp(firstAtCurrent.takenAt)
            weeksAtCurrent = max(Int(Date().timeIntervalSince(start) / 604_800), 0)
        }

        // Model the concentration across this week, sampled every six hours.
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        ) ?? calendar.startOfDay(for: .now)
        var points: [MedicationCurvePoint] = []
        for step in 0...(7 * 4) {
            let moment = weekStart.addingTimeInterval(Double(step) * 6 * 3600)
            points.append(MedicationCurvePoint(
                date: moment,
                level: DashboardMapping.medicationLevel(shots: payload.shots, at: moment)
            ))
        }

        let history = ordered.enumerated().reversed().map { index, shot in
            DoseRecord(
                week: index + 1,
                doseMg: shot.doseMg,
                date: DashboardService.parseTimestamp(shot.takenAt),
                site: InjectionSite(rawValue: shot.injectionSite)?.title
                    ?? shot.injectionSite.capitalized
            )
        }

        return MedicationDashboard(
            drugName: payload.plan?.name ?? "Semaglutide",
            titration: DoseTitration(
                level: level,
                weeksCompleted: min(weeksAtCurrent, 4),
                weeksPerLevel: 4,
                currentDoseMg: planDose
            ),
            nextDose: DashboardMapping.nextShot(payload),
            curve: MedicationCurve(
                points: points,
                therapeuticThreshold: planDose * 0.5
            ),
            insight: RivaInsight(
                message: payload.shots.isEmpty
                    ? "Log your first shot and the curve starts modelling the medication in your system."
                    : "Your level peaks a day or two after each shot and tapers before the next. That rhythm is normal."
            ),
            history: Array(history)
        )
    }
}

// MARK: - Tracker

struct APITrackerRepository: TrackerRepository {

    private let service: DashboardService

    init(service: DashboardService) {
        self.service = service
    }

    func trackerDashboard() async throws -> TrackerDashboard {
        let payload = try await service.fetch()
        let goals = payload.nutritionGoals
        let today = payload.today
        let weight = DashboardMapping.weightSummary(payload)
        let next = DashboardMapping.nextShot(payload)

        let recentDaily = payload.weights.reversed().suffix(7).map(\.pounds)

        let message: String
        if payload.shots.isEmpty {
            message = "Start with a shot log and a weight, and Riva starts coaching from your real numbers."
        } else if next.daysRemaining() <= 1 {
            message = next.daysRemaining() == 0
                ? "Today is **injection day**. \(next.suggestedSite) is up next."
                : "Tomorrow is **injection day**. \(next.suggestedSite) is up next."
        } else {
            message = "Next shot in **\(next.daysRemaining()) days**. Keep protein and water on pace this week."
        }

        return TrackerDashboard(
            intelligence: RivaInsight(message: message),
            weight: WeightTrend(
                currentLbs: weight.currentLbs,
                weeklyChangeLbs: weight.weeklyChangeLbs,
                recentDailyLbs: Array(recentDaily)
            ),
            hydration: HydrationStatus(
                glasses: (today?.waterOunces ?? 0) / 8,
                goalGlasses: max(goals.waterGoal / 8, 1)
            ),
            protein: ProteinStatus(
                grams: Double(today?.proteinGrams ?? 0),
                goalGrams: Double(max(goals.proteinGoal, 1))
            ),
            sideEffect: DashboardMapping.sideEffectReport(payload.sideEffectsToday),
            sleep: DashboardMapping.sleepStatus(payload.sleepCheckins)
        )
    }

    func weeklySummary() async throws -> WeeklySummary {
        let payload = try await service.fetch()
        let weight = DashboardMapping.weightSummary(payload)
        let next = DashboardMapping.nextShot(payload)
        let week = DateInterval(
            start: Date().addingTimeInterval(-6 * 86_400),
            end: Date()
        )

        let weekWeights = payload.weights.reversed().filter {
            DashboardService.parseTimestamp($0.measuredAt) >= week.start
        }
        let lastDose = payload.shots.first.map {
            DashboardService.parseTimestamp($0.takenAt)
        } ?? Date()

        let coachMessage: String
        if weight.weeklyChangeLbs < 0 {
            coachMessage = "You are down **\(RivaFormat.weight(abs(weight.weeklyChangeLbs))) lbs this week**. Whatever you are doing, it is working; protect the routine."
        } else if payload.weights.isEmpty {
            coachMessage = "No weights logged this week. One weigh-in on the same morning each week is enough to see the trend."
        } else {
            coachMessage = "Weight held steady this week. Plateaus are part of the curve; keep your protein up and stay the course."
        }

        return WeeklySummary(
            interval: week,
            weight: WeeklyWeightProgress(
                changeLbs: weight.weeklyChangeLbs,
                isOnTrack: weight.weeklyChangeLbs <= 0,
                dailyLbs: weekWeights.map(\.pounds),
                totalLostLbs: max(-weight.totalChangeLbs, 0),
                goalLbs: weight.targetLbs
            ),
            coachNote: CoachNote(coachName: "Remi", message: coachMessage),
            lastDoseDate: lastDose,
            nextDoseDate: next.date,
            calories: QuantityGoal(
                value: DashboardMapping.weekAverage(payload.weekNutrition) { $0.calories },
                goal: 2000
            ),
            protein: QuantityGoal(
                value: DashboardMapping.weekAverage(payload.weekNutrition) { $0.proteinGrams },
                goal: Double(max(payload.nutritionGoals.proteinGoal, 1))
            ),
            hydrationLitersPerDay: DashboardMapping.weekAverage(payload.weekNutrition) {
                $0.waterOunces
            } * 0.0295735,
            sleepAverageMinutes: 0
        )
    }
}
