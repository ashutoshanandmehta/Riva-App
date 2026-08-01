import Foundation

/// Types for correcting a scan after the fact: one candidate replacement for a
/// mis-detected item, the context the replacement service needs to suggest
/// good ones, and the derivations that rebuild a `ScanResult` around an edit.
///
/// Kept apart from `ScanModels.swift`, which mirrors the scan response and
/// stays a pure transport shape.

/// One candidate replacement for a detected item, from
/// `POST /v1/food-search`.
///
/// `matched` is true only when the food itself hit a USDA entry. A dish USDA
/// did not know was composed from a recipe whose ingredients were priced
/// against USDA — better than a bare guess, but still an estimate.
struct FoodSuggestion: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let portionDesc: String
    let portionGrams: Double
    let calories: Int
    let proteinGrams: Int
    let carbGrams: Int
    let fiberGrams: Int
    let fatG: Double
    let sugarG: Double
    let sodiumMg: Double
    let matched: Bool

    /// Local only — the payload carries no id, and name plus grams is stable
    /// across one editor session. Computed, so it is never encoded.
    var id: String { "\(name)|\(portionGrams)" }
}

/// What the replacement service needs to price a swap sensibly: the item we
/// got wrong, what else was on the plate to keep the meal coherent, and the
/// portion already measured there — a searched food keeps that portion, so
/// only the food changes.
struct FoodReplacementContext: Sendable, Equatable {
    let originalItem: String
    let plateContext: String?
    let otherItems: [String]
    let originalGrams: Double
    let originalPortionDesc: String

    init(
        originalItem: String,
        plateContext: String?,
        otherItems: [String],
        originalGrams: Double = 0,
        originalPortionDesc: String = ""
    ) {
        self.originalItem = originalItem
        self.plateContext = plateContext
        self.otherItems = otherItems
        self.originalGrams = originalGrams
        self.originalPortionDesc = originalPortionDesc
    }

    /// Context for replacing `index` in the list currently on screen.
    init(replacing index: Int, in items: [ScanItem], plate: String?) {
        let item = items.indices.contains(index) ? items[index] : nil
        self.init(
            originalItem: item?.name ?? "",
            plateContext: plate,
            otherItems: items.enumerated()
                .filter { $0.offset != index }
                .map { $0.element.name },
            originalGrams: item?.portionGrams ?? 0,
            originalPortionDesc: item?.portionDesc ?? ""
        )
    }
}

extension ScanItem {
    /// A new item built from a replacement the user picked.
    ///
    /// Every macro comes from the suggestion, which the server priced against
    /// USDA (or composed from a USDA-priced recipe), so a swap logs a complete
    /// day rather than dropping the item's carbs and fibre. `fdcId` and
    /// `fdcDescription` still clear: those identify the old match, not this one.
    func replaced(with suggestion: FoodSuggestion) -> ScanItem {
        ScanItem(
            name: suggestion.name,
            portionDesc: suggestion.portionDesc,
            portionGrams: suggestion.portionGrams,
            confidence: "user",
            calories: suggestion.calories,
            proteinGrams: suggestion.proteinGrams,
            carbGrams: suggestion.carbGrams,
            fiberGrams: suggestion.fiberGrams,
            extended: ExtendedNutrients(
                fatG: suggestion.fatG,
                sugarG: suggestion.sugarG,
                sodiumMg: suggestion.sodiumMg
            ),
            matched: suggestion.matched,
            fdcId: nil,
            fdcDescription: nil,
            source: "user",
            alternatives: []
        )
    }
}

extension ScanTotals {
    /// Sums the DB-aligned integer nutrients across items. Matches what the
    /// backend's `_assemble` does, which sums the same rounded per-item values.
    init(summing items: [ScanItem]) {
        self.init(
            calories: items.reduce(0) { $0 + $1.calories },
            proteinGrams: items.reduce(0) { $0 + $1.proteinGrams },
            carbGrams: items.reduce(0) { $0 + $1.carbGrams },
            fiberGrams: items.reduce(0) { $0 + $1.fiberGrams }
        )
    }
}

extension ScanResult {
    /// A copy carrying `items`, with `totals` and `nutritionDayDelta`
    /// recomputed so an accepted edit logs the corrected meal — the log path
    /// sends `nutritionDayDelta`, not a sum of items.
    ///
    /// Returns `self` untouched when nothing changed, so an unedited scan still
    /// logs exactly the numbers the server assembled.
    func replacingItems(_ items: [ScanItem]) -> ScanResult {
        guard items != self.items else { return self }
        let totals = ScanTotals(summing: items)
        return ScanResult(
            scanType: scanType,
            requestedMode: requestedMode,
            modeMismatch: modeMismatch,
            reason: reason,
            plate: plate,
            items: items,
            water: water,
            totals: totals,
            nutritionDayDelta: NutritionDelta(
                calories: totals.calories,
                proteinGrams: totals.proteinGrams,
                carbGrams: totals.carbGrams,
                fiberGrams: totals.fiberGrams,
                // Items never carry water; only a water reading does.
                waterOunces: nutritionDayDelta.waterOunces
            ),
            promptVersion: promptVersion,
            model: model
        )
    }
}
