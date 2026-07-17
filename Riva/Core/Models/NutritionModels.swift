import Foundation

/// One daily-nutrient goal tile (protein, water, …).
///
/// Display strings are provided by the data layer so new nutrient types can be
/// added server-side without a client release.
struct NutrientProgress: Identifiable, Equatable, Sendable {
    var id: String { title }
    /// Tile caption, e.g. "Protein".
    var title: String
    /// Value shown inside the ring, e.g. "95g" or "6".
    var valueText: String
    /// Line under the ring, e.g. "of 110g" or "of 8 glasses".
    var targetText: String
    /// Ring fill in `0...1`.
    var progress: Double
}

/// A coaching insight generated from the patient's logs.
struct RivaInsight: Equatable, Sendable {
    var message: String
}
