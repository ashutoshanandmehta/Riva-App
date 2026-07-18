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
}

struct HealthGoalFlags: Codable, Sendable, Equatable {
    let glp1Support: Bool
    let weightMgmt: Bool
    let nutritionDiet: Bool
    let musclePreserve: Bool
    let exerciseMove: Bool
    let sleepRecovery: Bool
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

    var id: String { rawValue }
}
