import Foundation

// MARK: - Practice catalog

/// The wellness practice categories. Raw values travel on the wire
/// (`POST /v1/log/wellness`), so they must match the backend CHECK constraint.
enum WellnessKind: String, Codable, Sendable, CaseIterable {
    case yoga
    case meditation
    case exercise
    case mind
    case sleep

    var title: String {
        switch self {
        case .yoga: "Yoga"
        case .meditation: "Meditation"
        case .exercise: "Exercise"
        case .mind: "Mind"
        case .sleep: "Sleep"
        }
    }

    var icon: String {
        switch self {
        case .yoga: "figure.yoga"
        case .meditation: "brain.head.profile"
        case .exercise: "figure.walk"
        case .mind: "heart.fill"
        case .sleep: "moon.zzz.fill"
        }
    }
}

/// One guided session in the local catalog. The single source of practice
/// metadata — the backend references entries by `id` only.
struct WellnessPractice: Identifiable, Sendable {
    let id: String
    let kind: WellnessKind
    let title: String
    let subtitle: String
    let minutes: Int
    /// The 11-character YouTube ID; `nil` renders a "coming soon" card.
    let videoID: String?
    let icon: String
    let description: String
    let prepSteps: [(icon: String, text: String)]

    var durationText: String { "\(minutes) min" }

    static func practice(id: String) -> WellnessPractice? {
        catalog.first { $0.id == id }
    }
}

// MARK: - Catalog entries

extension WellnessPractice {
    static let catalog: [WellnessPractice] = [
        WellnessPractice(
            id: "yoga_beginners",
            kind: .yoga,
            title: "Yoga for Beginners",
            subtitle: "Yoga with Adriene",
            minutes: 12,
            videoID: "j7rKKpwdXNE",
            icon: "figure.yoga",
            description: "A gentle introduction to yoga with Adriene Mishler. Perfect if you're new to yoga or returning after a break — no prior experience needed.",
            prepSteps: [
                ("tshirt", "Wear loose, comfortable clothing you can move freely in"),
                ("rectangle.portrait", "Clear a mat-sized space around you"),
                ("drop.fill", "Keep a glass of water nearby"),
                ("fork.knife.circle", "Avoid eating at least 1–2 hours before the session"),
            ]
        ),
        WellnessPractice(
            id: "yoga_weightloss",
            kind: .yoga,
            title: "Yoga for Weight Loss",
            subtitle: "Yoga with Adriene",
            minutes: 18,
            videoID: "6rh6pVGTqRU",
            icon: "flame.fill",
            description: "An energising flow to build strength, boost metabolism, and support your weight loss journey. Designed to complement your GLP-1 medication with mindful movement.",
            prepSteps: [
                ("tshirt", "Wear comfortable, breathable clothing"),
                ("rectangle.portrait", "Clear a 6×4 ft space and place your mat"),
                ("drop.fill", "Have water ready — this session builds heat"),
                ("clock", "Warm up with a few gentle stretches before starting"),
            ]
        ),
        WellnessPractice(
            id: "yoga_digestion",
            kind: .yoga,
            title: "Yoga for Digestion",
            subtitle: "Yoga with Adriene",
            minutes: 14,
            videoID: "hbguV_f6XOo",
            icon: "leaf.fill",
            description: "Targeted poses to ease bloating, reduce nausea, and support gut health. Particularly beneficial for managing common GLP-1 side effects like digestive discomfort.",
            prepSteps: [
                ("fork.knife.circle", "Practice at least 2–3 hours after your last meal"),
                ("tshirt", "Wear loose clothing around your midsection"),
                ("rectangle.portrait", "Have a mat and a cushion or blanket for support"),
                ("heart", "Move gently — this is a restorative, not an intense session"),
            ]
        ),
        WellnessPractice(
            id: "meditation_isha",
            kind: .meditation,
            title: "Isha Kriya",
            subtitle: "Sadhguru · Isha Foundation",
            minutes: 19,
            videoID: "EwQkfoKxRvo",
            icon: "moon.stars.fill",
            description: "Isha Kriya is a simple yet potent meditation offered freely by Sadhguru. Practiced daily for 48 days, it can bring clarity, stillness, and a natural sense of wellbeing — a meaningful complement to your GLP-1 journey.",
            prepSteps: [
                ("figure.mind.and.body", "Sit with your spine erect — on a chair or cross-legged on the floor"),
                ("hand.raised", "Rest your hands on your thighs, palms facing upward"),
                ("eye.slash", "Keep eyes 2/3 closed, gaze directed down along your nose"),
                ("bell.slash", "Find a quiet space and minimise disturbances for the full session"),
            ]
        ),
        WellnessPractice(
            id: "meditation_nsdr",
            kind: .meditation,
            title: "NSDR",
            subtitle: "Andrew Huberman · Huberman Lab",
            minutes: 11,
            videoID: "KHIbgSN2qAU",
            icon: "brain.head.profile",
            description: "Non-Sleep Deep Rest — a short, science-based protocol from Dr. Andrew Huberman to restore energy and calm the nervous system. Ten minutes of guided rest that can replace a nap.",
            prepSteps: [
                ("bed.double", "Lie down or recline somewhere comfortable"),
                ("eye.slash", "Close your eyes and let the audio guide you"),
                ("bell.slash", "Silence notifications for the full session"),
                ("clock", "Any time of day works — great after poor sleep"),
            ]
        ),
        WellnessPractice(
            id: "exercise_walk",
            kind: .exercise,
            title: "Power Walk",
            subtitle: "1 mile · Walk at Home",
            minutes: 17,
            videoID: "6KAUfPEFs60",
            icon: "figure.walk",
            description: "A one-mile indoor power walk with the Walk at Home team. Low-impact, no equipment, and easy to follow — a steady way to keep moving and protect muscle while losing weight.",
            prepSteps: [
                ("shoe", "Wear supportive shoes — carpet or a mat underfoot helps"),
                ("rectangle.portrait", "Clear enough space to step side to side"),
                ("drop.fill", "Keep water within reach"),
                ("heart", "March in place any time you need to ease the pace"),
            ]
        ),
        WellnessPractice(
            id: "mind_gratitude",
            kind: .mind,
            title: "Gratitude",
            subtitle: "Great Meditation",
            minutes: 10,
            videoID: "4P2SCgwXVxc",
            icon: "heart.fill",
            description: "A ten-minute guided gratitude meditation. Settling into what is already good lowers stress and steadies mood — a small daily reset that compounds over a long journey.",
            prepSteps: [
                ("figure.mind.and.body", "Sit comfortably with your back supported"),
                ("bell.slash", "Find a quiet spot and silence notifications"),
                ("eye.slash", "Close your eyes or soften your gaze"),
                ("clock", "Mornings work well — it sets the tone for the day"),
            ]
        ),
        WellnessPractice(
            id: "sleep_winddown",
            kind: .sleep,
            title: "Wind-down",
            subtitle: "Ally Boothroyd · Sarovara Yoga",
            minutes: 12,
            videoID: "LU1gFW7pavc",
            icon: "moon.zzz.fill",
            description: "A short yoga nidra to unwind the body and quiet the mind before bed. Better sleep supports appetite hormones and recovery — an easy evening ritual on GLP-1.",
            prepSteps: [
                ("bed.double", "Lie down in bed or somewhere you can fully relax"),
                ("lightbulb.slash", "Dim the lights and lower the volume"),
                ("bell.slash", "Put your phone in Do Not Disturb"),
                ("moon.zzz", "It's fine to drift off before the end"),
            ]
        ),
    ]
}

// MARK: - Wellness dashboard

/// Today's practice numbers for the hero card.
struct WellnessSummary: Sendable, Equatable {
    var minutesToday: Int
    var goalMinutes: Int
    var streakDays: Int

    static let empty = WellnessSummary(minutesToday: 0, goalMinutes: 45, streakDays: 0)
}

/// A catalog practice with the backend's (or fallback's) encouraging reason.
struct SuggestedPractice: Identifiable, Sendable {
    let practice: WellnessPractice
    let reason: String

    var id: String { practice.id }
}

/// Everything the Wellness tab renders in one load.
struct WellnessDashboard: Sendable {
    var summary: WellnessSummary
    var suggestions: [SuggestedPractice]
    /// True when the backend returned a wellness block — session logging is
    /// only offered then (silent degrade against an older backend).
    var canLogSessions: Bool
}

/// `POST /v1/log/wellness` response.
struct WellnessLogResult: Codable, Sendable {
    let day: String
    let minutesToday: Int
    let streakDays: Int
}
