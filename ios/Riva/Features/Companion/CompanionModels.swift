import Foundation

// MARK: - Message

struct CompanionMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    /// Set on the turn that staged a write. The card renders under the bubble,
    /// and the view model clears it once the user answers.
    var writePreview: CompanionWritePreview?

    enum Role { case user, bot }
}

// MARK: - Opening state

enum CompanionCopy {
    /// Questions the companion can genuinely answer from the read tools. Nothing
    /// here promises a number, a booking, or a clinician — the answer comes from
    /// the user's own logs.
    static let quickChips = [
        "How's my nausea trending?",
        "Am I hitting my protein?",
        "What did I weigh last week?",
        "What's left on today's list?"
    ]

    static let greeting = CompanionMessage(
        role: .bot,
        text: "I can look through your logs — weight, shots, food, side effects, "
            + "check-ins. Ask me anything, or tell me something to save."
    )
}
