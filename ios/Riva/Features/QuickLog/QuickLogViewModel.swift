import Foundation
import Observation

/// Drives one quick-log sheet (weight, shot, protein, side effects, or
/// sleep): holds the form fields, validates, saves, and reports the result.
@MainActor
@Observable
final class QuickLogViewModel {

    enum Phase: Equatable {
        case editing
        case saving
        case saved(String)
    }

    let kind: QuickLog
    private(set) var phase: Phase = .editing
    private(set) var errorMessage: String?
    /// The day's updated totals returned by a water/calories/protein log, so
    /// the dashboards can update optimistically instead of refetching.
    private(set) var savedTotals: DayTotals?
    /// Turns on after a Save attempt with missing fields, so the form can
    /// highlight exactly which inputs still need filling.
    private(set) var showValidation = false

    // Weight
    var weightText = ""

    // Shot
    var medicationName = "Semaglutide"
    var doseText = ""
    var site: InjectionSite?
    var comfortRating: Int?

    // Protein
    var proteinText = ""

    // Water
    var waterText = ""

    // Calories
    var caloriesText = ""

    // Side effects: selected effect → severity 1 to 5
    var severities: [SideEffect: Int] = [:]

    // Sleep
    var sleepCode: String?

    private let repository: any LogRepository

    init(kind: QuickLog, repository: any LogRepository) {
        self.kind = kind
        self.repository = repository
    }

    var canSave: Bool {
        switch kind {
        case .weight:
            return parsedWeight != nil
        case .shot:
            return !medicationName.trimmingCharacters(in: .whitespaces).isEmpty
                && parsedDose != nil && site != nil
        case .protein:
            return parsedProtein != nil
        case .water:
            return parsedWater != nil
        case .calories:
            return parsedCalories != nil
        case .sideEffects:
            return true
        case .sleep:
            return sleepCode != nil
        }
    }

    // MARK: Validation

    /// Per-field "still empty" flags, used with `showValidation` to highlight
    /// the shot form's inputs.
    var isMedicationMissing: Bool {
        medicationName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var isDoseMissing: Bool { parsedDose == nil }
    var isSiteMissing: Bool { site == nil }

    /// A friendly, specific message naming what still needs filling for the
    /// current kind, or nil when the form is ready to save.
    var validationMessage: String? {
        switch kind {
        case .weight:
            return parsedWeight == nil ? "Enter your weight in pounds (20–1500)." : nil
        case .shot:
            var missing: [String] = []
            if isMedicationMissing { missing.append("the medication name") }
            if isDoseMissing { missing.append("a dose (0–100 mg)") }
            if isSiteMissing { missing.append("an injection site") }
            guard !missing.isEmpty else { return nil }
            return "Please add \(Self.humanList(missing)) to log your shot."
        case .protein:
            return parsedProtein == nil ? "Enter a protein amount in grams (1–500)." : nil
        case .water:
            return parsedWater == nil ? "Enter a water amount in ounces (1–200)." : nil
        case .calories:
            return parsedCalories == nil ? "Enter a calorie amount (1–5000)." : nil
        case .sideEffects:
            return nil
        case .sleep:
            return sleepCode == nil ? "Pick how you slept last night." : nil
        }
    }

    /// Joins items as "a", "a and b", or "a, b, and c".
    private static func humanList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    func toggle(_ effect: SideEffect) {
        if severities[effect] == nil {
            severities[effect] = 2
        } else {
            severities[effect] = nil
        }
    }

    func save() async {
        guard phase == .editing else { return }
        // Incomplete form: guide the user to the empty fields instead of a
        // dead button.
        guard canSave else {
            showValidation = true
            errorMessage = validationMessage
            return
        }
        showValidation = false
        phase = .saving
        errorMessage = nil
        do {
            phase = .saved(try await performSave())
        } catch {
            phase = .editing
            errorMessage = error.localizedDescription
        }
    }

    private func performSave() async throws -> String {
        switch kind {
        case .weight:
            let result = try await repository.logWeight(pounds: parsedWeight ?? 0)
            return "Weight logged: \(Self.trimmed(result.pounds)) lbs."

        case .shot:
            let result = try await repository.logShot(
                medicationName: medicationName.trimmingCharacters(in: .whitespaces),
                doseMg: parsedDose ?? 0,
                site: site ?? .lowerLeftAbs,
                comfortRating: comfortRating
            )
            return "Shot logged: \(result.medicationName) \(Self.trimmed(result.doseMg)) mg."

        case .protein:
            let totals = try await repository.logProtein(grams: parsedProtein ?? 0)
            savedTotals = totals
            return "Protein logged. Today so far: \(totals.proteinGrams)g."

        case .water:
            let totals = try await repository.logWater(ounces: parsedWater ?? 0)
            savedTotals = totals
            return "Water logged. Today so far: \(totals.waterOunces) oz."

        case .calories:
            let totals = try await repository.logCalories(kcal: parsedCalories ?? 0)
            savedTotals = totals
            return "Calories logged. Today so far: \(totals.calories) kcal."

        case .sideEffects:
            let entries = severities
                .map { SideEffectEntry(effect: $0.key.rawValue, severity: $0.value) }
                .sorted { $0.effect < $1.effect }
            let result = try await repository.logSideEffects(entries)
            switch result.effects.count {
            case 0: return "No side effects logged for today."
            case 1: return "Logged 1 side effect for today."
            default: return "Logged \(result.effects.count) side effects for today."
            }

        case .sleep:
            let result = try await repository.logSleep(optionCode: sleepCode ?? "okay")
            return "Sleep logged: \(result.label)."
        }
    }

    // MARK: Parsing

    private var parsedWeight: Double? {
        guard let value = Double(weightText.trimmingCharacters(in: .whitespaces)),
              (20...1500).contains(value) else { return nil }
        return value
    }

    private var parsedDose: Double? {
        guard let value = Double(doseText.trimmingCharacters(in: .whitespaces)),
              value > 0, value <= 100 else { return nil }
        return value
    }

    private var parsedProtein: Int? {
        guard let value = Int(proteinText.trimmingCharacters(in: .whitespaces)),
              value > 0, value <= 500 else { return nil }
        return value
    }

    private var parsedWater: Int? {
        guard let value = Int(waterText.trimmingCharacters(in: .whitespaces)),
              value > 0, value <= 200 else { return nil }
        return value
    }

    private var parsedCalories: Int? {
        guard let value = Int(caloriesText.trimmingCharacters(in: .whitespaces)),
              value > 0, value <= 5000 else { return nil }
        return value
    }

    /// "0.50" reads as clutter; show "0.5" (and "184" for whole numbers).
    private static func trimmed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.2f", value)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}
