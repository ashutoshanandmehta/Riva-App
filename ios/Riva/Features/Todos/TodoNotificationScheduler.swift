import Foundation
import UserNotifications

/// Local notifications for to-dos. The server owns the to-dos; this owns only
/// the device-side alarms, rebuilt from the server list after every change so
/// the two can never drift.
///
/// Same `UNUserNotificationCenter` flow as the shot-day reminder in
/// `NotificationsSheet`, one request per open to-do instead of one total.
enum TodoNotificationScheduler {

    /// Identifier prefix, so reconciling only ever clears to-do requests and
    /// leaves `riva.shotReminder` alone.
    private static let prefix = "riva.todo."

    /// Asks once, then reports the standing answer. Returns false when the
    /// user has denied notifications — the caller still saves the to-do.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .denied
    }

    /// Rebuilds every to-do notification from `todos`.
    ///
    /// A daily to-do keeps its repeating trigger even once it is ticked off:
    /// the trigger describes the schedule, not today's state, and the app may
    /// not be opened again before tomorrow's alarm is due. Only finished or
    /// past one-offs get no request.
    static func reconcile(_ todos: [Todo], now: Date = .now) async {
        // Nothing to arm on a denied device, so skip the whole round trip.
        guard await isDenied() == false else { return }

        let center = UNUserNotificationCenter.current()
        // Identifiers are deterministic, so `add` replaces in place; this pass
        // only has to clear rows that were deleted or finished.
        let live = Set(todos.map { prefix + $0.id })
        let gone = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) && !live.contains($0) }
        if !gone.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: gone)
        }

        for todo in todos {
            guard let trigger = trigger(for: todo, now: now) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Riva to-do"
            content.body = todo.title
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: prefix + todo.id,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    /// Clears every to-do notification, e.g. on sign-out.
    static func clearAll() async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    // MARK: Triggers

    private static func trigger(for todo: Todo, now: Date) -> UNNotificationTrigger? {
        var components = DateComponents()
        components.hour = todo.remindHour
        components.minute = todo.remindMinute

        switch todo.repeatRule {
        case .daily:
            // Unconditional: today's checkmark must not cancel tomorrow's alarm.
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .once:
            // A finished one-off is done for good; nothing left to fire.
            guard !todo.isDone else { return nil }
            guard let day = todo.dueDate.flatMap(AccountDates.day) else { return nil }
            let calendar = Calendar.current
            guard let moment = calendar.date(
                bySettingHour: todo.remindHour, minute: todo.remindMinute, second: 0, of: day
            ), moment > now else {
                // Already past: scheduling it would fire immediately or never.
                return nil
            }
            let dated = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
            return UNCalendarNotificationTrigger(dateMatching: dated, repeats: false)
        }
    }
}
