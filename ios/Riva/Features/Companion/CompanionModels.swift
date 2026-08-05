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

// MARK: - Care team

struct CareTeamMember: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let systemImage: String
    let intro: String
}

enum CareTeamCopy {
    /// Care team messaging has no backend yet — these are introductions, not a
    /// live thread. Copy promises nothing beyond "when messaging opens".
    static let members: [CareTeamMember] = [
        CareTeamMember(
            name: "Dr. Amara Chen",
            role: "Clinician",
            systemImage: "stethoscope",
            intro: "Hi — I'm the clinician on your care team. When messaging opens, "
                + "I'll be the one reading your weight trend, your shot log and anything "
                + "you flag as a side effect before a dose changes. Until then, anything "
                + "urgent goes to your own prescriber or urgent care."
        ),
        CareTeamMember(
            name: "Maya Ellis",
            role: "Wellness coach",
            systemImage: "sparkles",
            intro: "I'm your wellness coach. The day-to-day is my patch — hitting your "
                + "protein, meals that stay down, sleep, and the small habits that make "
                + "the shots easier. Bring me the messy questions when messaging opens."
        )
    ]

    static let footnote = "Care team messaging isn't open yet — this is a preview of who you'll be talking to."
}
