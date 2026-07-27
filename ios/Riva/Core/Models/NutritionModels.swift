import Foundation

/// One daily-nutrient goal tile (calories, protein, carbs, …).
///
/// The data layer supplies numbers, not strings — the ring needs to subtract a
/// goal from a consumed value, and formatting the pair in one place keeps every
/// nutrient reading the same way.
struct NutrientProgress: Identifiable, Equatable, Sendable {
    var id: String { title }
    /// Row caption, e.g. "Protein".
    var title: String
    /// Consumed today, e.g. `96`.
    var value: Double
    /// Daily target, e.g. `130`.
    var goal: Double
    /// Suffix appended to both numbers, e.g. "g". Empty for a bare count.
    var unit: String

    /// Bar/ring fill in `0...1`. A missing goal reads as no progress rather
    /// than a divide-by-zero.
    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }

    /// How much of the goal is still open — never negative.
    var remaining: Double { max(0, goal - value) }

    /// e.g. "96".
    var valueText: String { Self.format(value) }

    /// e.g. "of 130g".
    var targetText: String { "of \(Self.format(goal))\(unit)" }

    /// e.g. "96 / 130g".
    var pairText: String { "\(Self.format(value)) / \(Self.format(goal))\(unit)" }

    /// Whole numbers lose the decimal point; anything else keeps one place.
    static func format(_ number: Double) -> String {
        number == number.rounded()
            ? String(Int(number))
            : String(format: "%.1f", number)
    }
}

/// A coaching insight generated from the patient's logs.
struct RivaInsight: Equatable, Sendable {
    var message: String
}
