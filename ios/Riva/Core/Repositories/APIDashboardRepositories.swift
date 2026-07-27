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

    struct Wellness: Codable, Sendable {
        let minutesToday: Int
        let streakDays: Int
        let goalMinutes: Int
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
    /// Optional so responses from a backend without wellness support still
    /// decode; readers degrade to zeros via `DashboardMapping.wellnessSummary`.
    let wellness: Wellness?
    /// Consecutive days with nutrition logged. Optional for the same reason —
    /// an older backend omits it and Home simply hides the streak chip.
    let streakDays: Int?
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

    /// Daily calorie goal. `NutritionGoals` has no calorie field from the
    /// backend yet, so this matches the flat 2000 kcal goal already used by
    /// `weeklySummary()` below.
    static let calorieGoalKcal = 2000

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

    /// A missing wellness block (old backend) reads as an honest zero day
    /// with the default 45-minute goal — never an error.
    static func wellnessSummary(_ wellness: DashboardPayload.Wellness?) -> WellnessSummary {
        guard let wellness else { return .empty }
        return WellnessSummary(
            minutesToday: wellness.minutesToday,
            goalMinutes: wellness.goalMinutes,
            streakDays: wellness.streakDays
        )
    }

    /// A calendar in the user's profile timezone. "Today" has to mean their
    /// local day — the same day the `log_*` functions compute server-side.
    static func profileCalendar(_ payload: DashboardPayload) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = TimeZone(identifier: payload.profile.timezone) {
            calendar.timeZone = zone
        }
        return calendar
    }

    /// The latest weight logged today, or nil. `payload.weights` is newest
    /// first, so the first match is the most recent one.
    static func weightToday(_ payload: DashboardPayload, now: Date = .now) -> Double? {
        let calendar = profileCalendar(payload)
        return payload.weights.first { entry in
            calendar.isDate(
                DashboardService.parseTimestamp(entry.measuredAt), inSameDayAs: now
            )
        }?.pounds
    }

    /// This week Monday→Sunday, each day marked logged only when that day has
    /// real nutrition activity. `week_nutrition` covers the last seven days, so
    /// every day of the current week is always in range.
    static func weekActivity(_ payload: DashboardPayload, now: Date = .now) -> [HomeDayStatus] {
        var calendar = profileCalendar(payload)
        calendar.firstWeekday = 2  // Monday
        let today = calendar.startOfDay(for: now)
        let daysFromMonday = (calendar.component(.weekday, from: today) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            return []
        }

        let logged = Set(
            payload.weekNutrition
                .filter { $0.calories > 0 || $0.waterOunces > 0 }
                .map(\.day)
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone

        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            let key = formatter.string(from: day)
            return HomeDayStatus(
                dayKey: key,
                letter: letters[offset],
                isToday: calendar.isDate(day, inSameDayAs: today),
                isLogged: logged.contains(key)
            )
        }
    }

    /// Days of history the Weight Tracking chart plots — matches its "Past
    /// month" badge. The payload carries up to 90 rows.
    static let weightChartDays = 30

    /// Progress toward the target weight, or nil when no goal is set. The
    /// journey is measured from the starting weight, so it is independent of
    /// the charted window.
    static func weightGoal(_ payload: DashboardPayload) -> WeightGoalProgress? {
        guard let target = payload.profile.goalWeight else { return nil }
        let ordered = payload.weights.reversed()
        let current = ordered.last?.pounds ?? payload.profile.startWeight ?? 0
        let start = payload.profile.startWeight ?? ordered.first?.pounds ?? current
        let progress: Double
        if start > target, start > 0 {
            progress = min(max((start - current) / (start - target), 0), 1)
        } else {
            progress = 0
        }
        return WeightGoalProgress(currentLbs: current, targetLbs: target, progress: progress)
    }

    static func weightSummary(_ payload: DashboardPayload, now: Date = .now) -> WeightSummary {
        let ordered = payload.weights.reversed()  // API is newest first
        let full = ordered.map {
            WeightPoint(date: DashboardService.parseTimestamp($0.measuredAt), weightLbs: $0.pounds)
        }
        let current = full.last?.weightLbs ?? payload.profile.startWeight ?? 0
        // The journey total is measured against the whole history, so read the
        // starting weight before the chart window trims anything away.
        let start = payload.profile.startWeight ?? full.first?.weightLbs ?? current

        var history = trimmedToChartWindow(full, now: now)
        if history.isEmpty, current > 0 {
            // A single synthetic point keeps the chart axes stable.
            history = [WeightPoint(date: now, weightLbs: current)]
        }

        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let weekBase = full.last(where: { $0.date <= weekAgo })?.weightLbs
            ?? full.first?.weightLbs ?? current

        return WeightSummary(
            history: history,
            currentLbs: current,
            weeklyChangeLbs: current - weekBase,
            totalChangeLbs: current - start,
            goal: weightGoal(payload)
        )
    }

    /// The trailing `weightChartDays` of history. Someone whose last weigh-in
    /// predates the window keeps that one reading rather than losing the chart.
    private static func trimmedToChartWindow(
        _ history: [WeightPoint], now: Date
    ) -> [WeightPoint] {
        let cutoff = now.addingTimeInterval(-Double(weightChartDays) * 86_400)
        let recent = history.filter { $0.date >= cutoff }
        return recent.isEmpty ? Array(history.suffix(1)) : recent
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
        let level = DashboardMapping.medicationLevel(shots: payload.shots)
        let planDose = payload.plan?.currentDoseMg ?? 0
        let goals = payload.nutritionGoals
        let today = payload.today

        let firstName = payload.profile.name
            .split(separator: " ").first.map(String.init) ?? "there"

        return HomeSnapshot(
            user: UserProfile(firstName: firstName == "there" ? "there" : firstName),
            quote: "Consistency is your superpower.",
            medicationLevel: MedicationLevelEstimate(
                currentMg: (level * 100).rounded() / 100,
                peakMg: max(planDose * 2, level, 0.5),
                explanation: payload.shots.isEmpty
                    ? "Log your first shot and Riva estimates the medication in your system through the week."
                    : "Estimated from your logged shots with a one week half life. Solid is past, dashed projects ahead."
            ),
            nextShot: DashboardMapping.nextShot(payload),
            // Calories drive the ring; protein/carbs/fiber are the macro bars.
            // Hydration lives on its own Tracker card, so it is not repeated here.
            nutrients: [
                NutrientProgress(
                    title: "Calories",
                    value: Double(today?.calories ?? 0),
                    goal: Double(DashboardMapping.calorieGoalKcal),
                    unit: " kcal"
                ),
                NutrientProgress(
                    title: "Protein",
                    value: Double(today?.proteinGrams ?? 0),
                    goal: Double(goals.proteinGoal),
                    unit: "g"
                ),
                NutrientProgress(
                    title: "Carbs",
                    value: Double(today?.carbGrams ?? 0),
                    goal: Double(goals.carbGoal),
                    unit: "g"
                ),
                NutrientProgress(
                    title: "Fiber",
                    value: Double(today?.fiberGrams ?? 0),
                    goal: Double(goals.fiberGoal),
                    unit: "g"
                ),
            ],
            week: DashboardMapping.weekActivity(payload),
            streakDays: payload.streakDays ?? 0,
            weightTodayLbs: DashboardMapping.weightToday(payload),
            goal: DashboardMapping.weightGoal(payload)
        )
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

        return TrackerDashboard(
            weight: weight,
            hydration: HydrationStatus(
                glasses: (today?.waterOunces ?? 0) / 8,
                goalGlasses: max(goals.waterGoal / 8, 1)
            ),
            protein: ProteinStatus(
                grams: Double(today?.proteinGrams ?? 0),
                goalGrams: Double(max(goals.proteinGoal, 1))
            ),
            calorie: CalorieStatus(
                calories: today?.calories ?? 0,
                goalCalories: DashboardMapping.calorieGoalKcal
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
                goalLbs: weight.goal?.targetLbs ?? weight.currentLbs
            ),
            coachNote: CoachNote(message: coachMessage),
            lastDoseDate: lastDose,
            nextDoseDate: next.date,
            calories: QuantityGoal(
                value: DashboardMapping.weekAverage(payload.weekNutrition) { $0.calories },
                goal: Double(DashboardMapping.calorieGoalKcal)
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
