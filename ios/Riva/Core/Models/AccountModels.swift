import Foundation

// MARK: - Server payloads (snake_case wire, decoded with .convertFromSnakeCase)

/// The user's profile row as the backend returns it.
struct AccountProfile: Codable, Sendable, Equatable {
    let name: String
    let dateOfBirth: String?
    let gender: String?
    let clinicianName: String?
    let startWeight: Double?
    let goalWeight: Double?
    let heightInches: Double?
    let timezone: String
}

struct NutritionGoals: Codable, Sendable, Equatable {
    let proteinGoal: Int
    let carbGoal: Int
    let fiberGoal: Int
    let waterGoal: Int
    /// Daily wellness minutes goal; optional so payloads from a backend
    /// without wellness support still decode.
    let wellnessMinutesGoal: Int?
}

struct HealthGoalFlags: Codable, Sendable, Equatable {
    let glp1Support: Bool
    let weightMgmt: Bool
    let nutritionDiet: Bool
    let musclePreserve: Bool
    let exerciseMove: Bool
    let sleepRecovery: Bool
    /// Optional, not defaulted: synthesised `Decodable` ignores property
    /// defaults and throws on a missing key, so a non-optional here would fail
    /// to decode against a backend that has not shipped migration 0006 yet.
    var weightMaintain: Bool?

    var wantsWeightMaintenance: Bool { weightMaintain ?? false }
}

struct MedicationPlan: Codable, Sendable, Equatable {
    let name: String
    let currentDoseMg: Double
    let cadenceDays: Int
    let doseFrequency: String
    let reminderDescription: String?
    let startDate: String?
}

/// Everything `GET /v1/me` returns in one shot.
struct AccountBundle: Codable, Sendable, Equatable {
    let profile: AccountProfile
    let nutritionGoals: NutritionGoals
    let healthGoals: HealthGoalFlags
    let plan: MedicationPlan?
}

struct WeightEntry: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let pounds: Double
    let doseMg: Double?
    let measuredAt: String
}

struct ShotEntry: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let medicationName: String
    let doseMg: Double
    let takenAt: String
    let injectionSite: String
    let comfortRating: Int?
}

/// One day's side-effect log with its reported effects inlined.
struct SideEffectDayLog: Codable, Sendable, Equatable, Identifiable {
    let logDate: String
    let note: String?
    let effects: [SideEffectEntry]

    var id: String { logDate }
}

// MARK: - Update bodies (nil fields are omitted, so any subset can be sent)

struct ProfileUpdate: Encodable, Sendable {
    var name: String?
    var dateOfBirth: String?
    var gender: String?
    var clinicianName: String?
    var startWeight: Double?
    var goalWeight: Double?
    var heightInches: Double?
    var timezone: String?
}

struct GoalsUpdate: Encodable, Sendable {
    var proteinGoal: Int?
    var carbGoal: Int?
    var fiberGoal: Int?
    var waterGoal: Int?
    var wellnessMinutesGoal: Int?
}

/// The onboarding "What brings you to The Peptide Company?" choices, one per
/// `health_goals` flag in the database.
enum OnboardingGoal: String, Sendable, Identifiable, CaseIterable {
    case weightMgmt = "weight_mgmt"
    case weightMaintain = "weight_maintain"
    case glp1Support = "glp1_support"
    case nutritionDiet = "nutrition_diet"
    case musclePreserve = "muscle_preserve"
    case exerciseMove = "exercise_move"
    case sleepRecovery = "sleep_recovery"

    /// What the signup intake form offers. Deliberately narrower than
    /// `allCases`: the rest stay in the enum so accounts that already chose
    /// them keep decoding, and so the profile's goal editor can still show
    /// the full set.
    static let intakeOptions: [OnboardingGoal] = [.weightMgmt, .weightMaintain]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weightMgmt: "Lose weight"
        case .weightMaintain: "Maintain weight"
        case .glp1Support: "GLP-1 support"
        case .nutritionDiet: "Nutrition and diet"
        case .musclePreserve: "Preserve muscle"
        case .exerciseMove: "Exercise and movement"
        case .sleepRecovery: "Sleep and recovery"
        }
    }

    var subtitle: String {
        switch self {
        case .weightMgmt: "Reach a healthier weight and keep it off."
        case .weightMaintain: "Hold steady where I am today."
        case .glp1Support: "Guidance through my medication journey."
        case .nutritionDiet: "Eat better with less guesswork."
        case .musclePreserve: "Protect strength while losing weight."
        case .exerciseMove: "Stay active in a way that lasts."
        case .sleepRecovery: "Rest well and recover fully."
        }
    }

    var systemImage: String {
        switch self {
        case .weightMgmt: "arrow.down.right.circle"
        case .weightMaintain: "equal.circle"
        case .glp1Support: "syringe"
        case .nutritionDiet: "fork.knife"
        case .musclePreserve: "figure.strengthtraining.traditional"
        case .exerciseMove: "figure.walk"
        case .sleepRecovery: "moon.zzz"
        }
    }
}

/// Full-set update for the health goal flags (onboarding submits the
/// complete selection, so unselected goals are explicitly false).
struct HealthGoalsUpdate: Encodable, Sendable {
    let glp1Support: Bool
    let weightMgmt: Bool
    let weightMaintain: Bool
    let nutritionDiet: Bool
    let musclePreserve: Bool
    let exerciseMove: Bool
    let sleepRecovery: Bool

    init(selected: Set<OnboardingGoal>) {
        glp1Support = selected.contains(.glp1Support)
        weightMgmt = selected.contains(.weightMgmt)
        weightMaintain = selected.contains(.weightMaintain)
        nutritionDiet = selected.contains(.nutritionDiet)
        musclePreserve = selected.contains(.musclePreserve)
        exerciseMove = selected.contains(.exerciseMove)
        sleepRecovery = selected.contains(.sleepRecovery)
    }
}

struct PlanUpdate: Encodable, Sendable {
    var name: String?
    var currentDoseMg: Double?
    var cadenceDays: Int?
    var reminderDescription: String?
}

// MARK: - Navigation

/// The account settings sheets reachable from the profile screen.
enum AccountSheet: String, Sendable, Identifiable, CaseIterable {
    case editProfile
    case editGoals
    case doseSettings
    case injectionDay
    case siteRotation
    case notifications
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editProfile: "Edit Profile"
        case .editGoals: "Edit Goals"
        case .doseSettings: "Dose Settings"
        case .injectionDay: "Injection Day"
        case .siteRotation: "Site Rotation"
        case .notifications: "Notifications"
        case .privacy: "Privacy and Security"
        }
    }

    var systemImage: String {
        switch self {
        case .editProfile: "pencil"
        case .editGoals: "flag"
        case .doseSettings: "syringe"
        case .injectionDay: "calendar"
        case .siteRotation: "arrow.trianglehead.2.clockwise.rotate.90"
        case .notifications: "bell"
        case .privacy: "lock"
        }
    }
}

/// History and info detail screens presented over the dashboards.
enum DetailScreen: String, Sendable, Identifiable, CaseIterable {
    case shotHistory
    case weightHistory
    case sideEffectsHistory
    case curveInfo
    case caloriesHistory
    case hydrationHistory
    case proteinHistory

    var id: String { rawValue }
}
