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

    // Weight
    var weightText = ""

    // Shot
    var medicationName = "Semaglutide"
    var doseText = ""
    var site: InjectionSite?
    var comfortRating: Int?

    // Protein
    var proteinText = ""

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
        case .sideEffects:
            return true
        case .sleep:
            return sleepCode != nil
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
        guard canSave, phase == .editing else { return }
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
            return "Protein logged. Today so far: \(totals.proteinGrams)g."

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

    /// "0.50" reads as clutter; show "0.5" (and "184" for whole numbers).
    private static func trimmed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.2f", value)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}
