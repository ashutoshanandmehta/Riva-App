import Foundation

/// What a to-do is about. Food, water, and weight open the Snap feature that
/// already logs them; custom is a plain reminder with nowhere to route.
enum TodoCategory: String, Codable, Sendable, Identifiable, CaseIterable {
    case food
    case water
    case weight
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: "Food"
        case .water: "Water"
        case .weight: "Weight"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .food: "fork.knife"
        case .water: "drop"
        case .weight: "scalemass"
        case .custom: "star"
        }
    }

    /// The Snap action a to-do row opens, or nil for a custom reminder.
    var snapAction: SnapAction? {
        switch self {
        case .food: .food
        case .water: .water
        case .weight: .weight
        case .custom: nil
        }
    }
}

/// How often a to-do fires.
enum TodoRepeat: String, Codable, Sendable, Identifiable, CaseIterable {
    case daily
    case once

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .once: "Once"
        }
    }
}

/// One to-do as the backend returns it. `isDone` is resolved server-side
/// against the profile timezone, so a daily to-do reopens on its own each
/// morning and the client never does day math.
struct Todo: Identifiable, Codable, Sendable, Equatable {
    let id: String
    var title: String
    var category: TodoCategory
    var repeatRule: TodoRepeat
    var remindHour: Int
    var remindMinute: Int
    /// The day a `once` to-do happens, `yyyy-MM-dd`. Always nil for `daily`.
    var dueDate: String?
    var isDone: Bool

    /// Trailing label on the card row: "Daily", "8:00 AM", or "Tue 8:00 AM".
    var scheduleText: String {
        let time = TodoDates.timeText(hour: remindHour, minute: remindMinute)
        switch repeatRule {
        case .daily:
            return "Daily"
        case .once:
            guard let day = dueDate.flatMap(AccountDates.day) else { return time }
            return "\(TodoDates.weekdayText(day)) \(time)"
        }
    }
}

/// The editor's working copy. A nil `id` means "create"; a set one means
/// "edit that to-do", which is exactly what `POST /v1/todos` expects.
struct TodoDraft: Equatable, Sendable {
    var id: String?
    var title: String
    var category: TodoCategory
    var repeatRule: TodoRepeat
    /// Reminder time; only the hour and minute are sent.
    var time: Date
    /// The day a `once` to-do happens. Ignored when the rule is `daily`.
    var day: Date

    /// A blank draft for "Set a to-do", defaulting to 9:00 AM today.
    init(now: Date = .now) {
        id = nil
        title = ""
        category = .custom
        repeatRule = .daily
        time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        day = now
    }

    /// Pre-populated from an existing to-do for "Edit to-do".
    init(todo: Todo, now: Date = .now) {
        id = todo.id
        title = todo.title
        category = todo.category
        repeatRule = todo.repeatRule
        time = Calendar.current.date(
            bySettingHour: todo.remindHour, minute: todo.remindMinute, second: 0, of: now
        ) ?? now
        day = todo.dueDate.flatMap(AccountDates.day) ?? now
    }

    var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(trimmed.count)
    }
}

/// Display formatting specific to to-dos. Day strings go through
/// `AccountDates`, which already owns the backend's `yyyy-MM-dd` format.
enum TodoDates {

    /// Locale-aware clock time from a bare hour and minute.
    static func timeText(hour: Int, minute: Int) -> String {
        let components = DateComponents(hour: hour, minute: minute)
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func weekdayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }
}
