import Foundation

/// What the user chose to log. A hint for the scan pipeline, never a filter:
/// the service reports what is actually in the photo and flags a mismatch.
enum ScanMode: String, Sendable, Identifiable, CaseIterable {
    case auto
    case food
    case water

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .food: "Food"
        case .water: "Water"
        }
    }
}

/// What the scan service detected in the photo.
enum ScanType: String, Codable, Sendable, Equatable {
    case food
    case water
    case beverage
    case notFood = "not_food"
}

struct ExtendedNutrients: Codable, Sendable, Equatable {
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
}

/// One detected food or drink item, with DB-aligned integer nutrients.
/// `matched == true` means the numbers were recomputed from a USDA
/// FoodData Central entry rather than estimated by the vision model.
struct ScanItem: Codable, Sendable, Equatable {
    let name: String
    let portionDesc: String
    let portionGrams: Double
    let confidence: String
    let calories: Int
    let proteinGrams: Int
    let carbGrams: Int
    let fiberGrams: Int
    let extended: ExtendedNutrients
    let matched: Bool
    let fdcId: Int?
    let fdcDescription: String?
    let source: String
    let alternatives: [String]
}

struct WaterReading: Codable, Sendable, Equatable {
    let containerType: String
    let volumeOz: Int
    let volumeMl: Int
    let glasses: Double
}

struct ScanTotals: Codable, Sendable, Equatable {
    let calories: Int
    let proteinGrams: Int
    let carbGrams: Int
    let fiberGrams: Int
}

/// The exact increments the backend applies to the user's `nutrition_days`
/// row. Only plain water fills `waterOunces`; beverages count as calories.
struct NutritionDelta: Codable, Sendable, Equatable {
    let calories: Int
    let proteinGrams: Int
    let carbGrams: Int
    let fiberGrams: Int
    let waterOunces: Int
}

/// Full result of one photo scan, mirroring the scan service response.
struct ScanResult: Codable, Sendable, Equatable {
    let scanType: ScanType
    let requestedMode: String
    let modeMismatch: Bool
    let reason: String?
    let plate: String?
    let items: [ScanItem]
    let water: WaterReading?
    let totals: ScanTotals
    let nutritionDayDelta: NutritionDelta
    let promptVersion: String
    let model: String
}

/// The user's running `nutrition_days` totals after an accepted log.
struct DayTotals: Codable, Sendable, Equatable {
    let day: String
    let calories: Int
    let proteinGrams: Int
    let carbGrams: Int
    let fiberGrams: Int
    let waterOunces: Int
}
