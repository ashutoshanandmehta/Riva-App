import Foundation

/// Wellness tab reads: today's practice summary plus suggested practices.
/// Session writes go through `LogRepository.logWellnessSession`.
protocol WellnessRepository: Sendable {
    /// Summary and suggestions in one load. Implementations degrade softly:
    /// a backend without wellness support yields zeros and local fallback
    /// suggestions rather than an error.
    func dashboard() async throws -> WellnessDashboard
}

/// Deterministic time-of-day suggestions used whenever the backend's
/// LLM-picked list is unavailable (old backend, network error, bad payload).
enum WellnessFallback {

    static func suggestions(
        hour: Int = Calendar.current.component(.hour, from: .now)
    ) -> [SuggestedPractice] {
        let primaryID: String
        let primaryReason: String
        switch hour {
        case 5..<12:
            primaryID = "yoga_beginners"
            primaryReason = "A gentle flow is a great way to start the day."
        case 18..<24, 0..<5:
            primaryID = "sleep_winddown"
            primaryReason = "Wind down tonight and let your body recover."
        default:
            primaryID = "mind_gratitude"
            primaryReason = "A few grateful minutes can reset your afternoon."
        }
        let secondaryID = primaryID == "mind_gratitude" ? "meditation_nsdr" : "mind_gratitude"
        let secondaryReason = secondaryID == "mind_gratitude"
            ? "A short gratitude practice steadies mood on busy days."
            : "Ten minutes of deep rest restores energy any time."

        return [primaryID, secondaryID].compactMap { id in
            guard let practice = WellnessPractice.practice(id: id) else { return nil }
            let reason = id == primaryID ? primaryReason : secondaryReason
            return SuggestedPractice(practice: practice, reason: reason)
        }
    }
}
