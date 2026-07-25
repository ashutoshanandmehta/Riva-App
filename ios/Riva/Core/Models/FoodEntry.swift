import Foundation

/// One logged nutrition entry as `GET /v1/food-entries` returns it
/// (snake_case wire, decoded with `.convertFromSnakeCase`). Backs the
/// per-metric history sheets on the Tracker cards.
struct FoodEntry: Codable, Sendable, Equatable, Identifiable {
    let day: String
    let scanType: String
    let items: [FoodEntryItem]
    let calories: Int
    let proteinGrams: Int
    let waterOunces: Int
    let createdAt: String

    /// No stable server id, so the created-at timestamp identifies the row.
    var id: String { createdAt }

    /// A friendly label for the entry: the first item, or a sensible
    /// fallback when the log carried no named items.
    var displayName: String {
        items.first?.name ?? (scanType == "water" ? "Water" : "Logged item")
    }
}

/// One named item inside a `FoodEntry`.
struct FoodEntryItem: Codable, Sendable, Equatable {
    let name: String
}
