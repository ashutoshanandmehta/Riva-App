import Foundation

// MARK: - Message

struct CompanionMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    var triage: TriageCard?

    enum Role { case user, bot }
}

// MARK: - Triage card

struct TriageCard {
    let level: TriageLevel
    let flagLabel: String
    let actionTitle: String
    let actionBody: String
    let ctaLabel: String
    let secondaryLabel: String?

    enum TriageLevel {
        case green, amber, red

        var dotColor: String { // hex
            switch self {
            case .green: "#3E6349"
            case .amber: "#C8A454"
            case .red:   "#A5391F"
            }
        }
    }
}

// MARK: - Triage classification (keyword-based UI shell)

enum CompanionTriage {
    private static let redWords = [
        "chest pain", "chest", "breathe", "breathing", "faint",
        "passed out", "blood", "severe", "throat", "numb", "vision"
    ]
    private static let amberWords = [
        "nauseous", "nausea", "vomit", "throw up", "dizzy", "headache",
        "constipated", "diarrhea", "reflux", "heartburn", "injection site",
        "bruise", "fatigue", "sick", "skip a dose", "skip"
    ]

    static func classify(_ input: String) -> CompanionMessage {
        let lower = input.lowercased()

        if redWords.contains(where: { lower.contains($0) }) {
            return CompanionMessage(role: .bot,
                text: "Okay — this one I'm not going to sit on. Stop what you're doing and get help now. Please don't drive yourself.",
                triage: TriageCard(
                    level: .red,
                    flagLabel: "Right now · emergency",
                    actionTitle: "Call an ambulance",
                    actionBody: "911 dispatch. Your care team gets your meds and last dose sent over automatically.",
                    ctaLabel: "Call 911",
                    secondaryLabel: "Ping my care team"
                ))
        }

        if amberWords.contains(where: { lower.contains($0) }) {
            return CompanionMessage(role: .bot,
                text: "Super common on GLP-1s — but at your dose I'd rather a doctor eyeball it today than have you tough it out.",
                triage: TriageCard(
                    level: .amber,
                    flagLabel: "Get checked · today",
                    actionTitle: "Quick video call today",
                    actionBody: "11:20 AM with Dr. Reyes, about 12 min. Or just ring the care line: (888) 402-7731.",
                    ctaLabel: "Grab 11:20 AM",
                    secondaryLabel: "Call the care line"
                ))
        }

        return CompanionMessage(role: .bot,
            text: "Nothing scary here — you're good. Here's what I'd do next based on your logs.",
            triage: TriageCard(
                level: .green,
                flagLabel: "All good · handle it yourself",
                actionTitle: "Keep the streak alive",
                actionBody: "Get your water in, hit 130g protein, log before bed. I'll check on you after Tuesday's shot.",
                ctaLabel: "Add to today",
                secondaryLabel: nil
            ))
    }

    static let quickChips = [
        "My chest hurts",
        "Feeling nauseous",
        "Can I skip a shot?",
        "Cheap protein ideas"
    ]

    static let greeting = CompanionMessage(
        role: .bot,
        text: "Morning — 3 of 4 done today, shot's on Tuesday. Anything feeling weird?"
    )
}
