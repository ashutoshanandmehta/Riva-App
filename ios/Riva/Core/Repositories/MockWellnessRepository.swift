import Foundation

/// Canned wellness data for previews (the reference design's numbers).
struct MockWellnessRepository: WellnessRepository {

    func dashboard() async throws -> WellnessDashboard {
        try? await Task.sleep(for: .milliseconds(400))
        return WellnessDashboard(
            summary: WellnessSummary(minutesToday: 24, goalMinutes: 45, streakDays: 5),
            suggestions: [
                SuggestedPractice(
                    practice: WellnessPractice.practice(id: "mind_gratitude")!,
                    reason: "You're on a 5-day streak — a grateful pause keeps it going."
                ),
                SuggestedPractice(
                    practice: WellnessPractice.practice(id: "sleep_winddown")!,
                    reason: "Sleep looked light this week; tonight, wind down early."
                ),
            ],
            canLogSessions: true
        )
    }
}
