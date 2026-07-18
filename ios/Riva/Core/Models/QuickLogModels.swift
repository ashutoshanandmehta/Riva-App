import Foundation

/// The quick-log flows reachable from the snap menu and dashboard cards.
enum QuickLog: String, Sendable, Identifiable, CaseIterable {
    case weight
    case shot
    case protein
    case sideEffects
    case sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "Log Weight"
        case .shot: "Log Shot"
        case .protein: "Log Protein"
        case .sideEffects: "Log Side Effects"
        case .sleep: "Sleep Quality"
        }
    }

    var systemImage: String {
        switch self {
        case .weight: "scalemass"
        case .shot: "syringe"
        case .protein: "fork.knife"
        case .sideEffects: "exclamationmark.bubble"
        case .sleep: "moon.zzz"
        }
    }
}

/// Injection sites, matching the database enum.
enum InjectionSite: String, Sendable, Identifiable, CaseIterable {
    case leftArm = "left_arm"
    case rightArm = "right_arm"
    case lowerLeftAbs = "lower_left_abs"
    case lowerRightAbs = "lower_right_abs"
    case leftThigh = "left_thigh"
    case rightThigh = "right_thigh"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftArm: "Left arm"
        case .rightArm: "Right arm"
        case .lowerLeftAbs: "Lower left abs"
        case .lowerRightAbs: "Lower right abs"
        case .leftThigh: "Left thigh"
        case .rightThigh: "Right thigh"
        }
    }
}

/// Trackable side effects, matching the database enum.
enum SideEffect: String, Sendable, Identifiable, CaseIterable {
    case nausea
    case headache
    case fatigue
    case constipation
    case diarrhea
    case dizziness
    case bloating
    case heartburn
    case foodNoise = "food_noise"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foodNoise: "Food noise"
        default: rawValue.capitalized
        }
    }
}

/// One sleep answer choice. Codes match the seeded check-in options.
struct SleepOption: Sendable, Identifiable, Equatable {
    let code: String
    let label: String

    var id: String { code }

    static let all = [
        SleepOption(code: "excellent", label: "Excellent"),
        SleepOption(code: "good", label: "Good"),
        SleepOption(code: "okay", label: "Okay"),
        SleepOption(code: "poor", label: "Poor"),
        SleepOption(code: "terrible", label: "Terrible"),
    ]
}

// MARK: - Server results

struct WeightLogResult: Codable, Sendable, Equatable {
    let weightId: String
    let pounds: Double
    let doseMg: Double?
    let measuredAt: String
}

struct ShotLogResult: Codable, Sendable, Equatable {
    let shotId: String
    let medicationName: String
    let doseMg: Double
    let takenAt: String
    let injectionSite: String
}

struct SideEffectEntry: Codable, Sendable, Equatable {
    let effect: String
    let severity: Int
}

struct SideEffectsLogResult: Codable, Sendable, Equatable {
    let logDate: String?
    let effects: [SideEffectEntry]
}

struct CheckinLogResult: Codable, Sendable, Equatable {
    let checkinDate: String
    let questionId: String
    let optionCode: String
    let label: String
    let value: Int
}
