import SwiftUI
import UserNotifications

/// One real reminder: a weekly local notification on shot day. The toggle
/// and time apply immediately and persist across launches.
struct NotificationsSheet: View {
    let onClose: () -> Void

    @State private var model: NotificationsViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: NotificationsViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            AccountSheetHeader(sheet: .notifications)

            switch model.phase {
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .ready:
                settings
                Spacer(minLength: RivaSpacing.xs)
                Button("Done", action: onClose)
                    .buttonStyle(.rivaPrimary)
                    .padding(.horizontal, RivaSpacing.screenMargin)
            }
        }
        .padding(.top, RivaSpacing.xl)
        .padding(.bottom, RivaSpacing.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
        .task { await model.load() }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            VStack(spacing: RivaSpacing.sm) {
                Toggle(
                    "Shot day reminder",
                    isOn: Binding(
                        get: { model.isEnabled },
                        set: { newValue in Task { await model.setEnabled(newValue) } }
                    )
                )
                .font(RivaFont.body)
                .foregroundStyle(RivaColor.textPrimary)
                .tint(RivaColor.brand)

                if model.isEnabled {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { model.time },
                            set: { newValue in Task { await model.setTime(newValue) } }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
                    .tint(RivaColor.brand)
                }
            }
            .padding(.horizontal, RivaSpacing.md)
            .padding(.vertical, 12)
            .background(
                RivaColor.fillNeutral,
                in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
            )

            if model.isEnabled {
                Text("Repeats every \(model.weekdayName).")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }

            if model.permissionDenied {
                Text("Notifications for Riva are turned off. Allow them in Settings to get this reminder.")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .animation(.default, value: model.isEnabled)
    }
}

/// Owns the weekly shot reminder: permission, scheduling, and persistence.
@MainActor
@Observable
final class NotificationsViewModel {

    enum Phase: Equatable {
        case loading
        case ready
    }

    private static let reminderID = "riva.shotReminder"
    private static let enabledKey = "riva.shotReminder.enabled"
    private static let hourKey = "riva.shotReminder.hour"
    private static let minuteKey = "riva.shotReminder.minute"

    private(set) var phase: Phase = .loading
    private(set) var isEnabled = false
    private(set) var time = Date.now
    private(set) var permissionDenied = false
    private(set) var weekdayName = "Sunday"

    private var plan: MedicationPlan?
    private let account: any AccountRepository

    init(account: any AccountRepository) {
        self.account = account
    }

    func load() async {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: Self.hourKey) as? Int ?? 9
        let minute = defaults.object(forKey: Self.minuteKey) as? Int ?? 0
        time = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        isEnabled = defaults.bool(forKey: Self.enabledKey)

        plan = try? await account.me().plan
        weekdayName = resolvedWeekdayName()

        // If permission was revoked in Settings since last time, reflect it.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if isEnabled, settings.authorizationStatus == .denied {
            isEnabled = false
            permissionDenied = true
            persist()
        }
        phase = .ready
    }

    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        guard enabled else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
            persist()
            return
        }

        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            isEnabled = false
            permissionDenied = true
            persist()
            return
        }
        permissionDenied = false
        await schedule()
        persist()
    }

    func setTime(_ newTime: Date) async {
        time = newTime
        persist()
        if isEnabled {
            await schedule()
        }
    }

    // MARK: Scheduling

    private func schedule() async {
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = RivaWeekday.calendarIndex(of: resolvedWeekdayName())
        components.hour = calendar.component(.hour, from: time)
        components.minute = calendar.component(.minute, from: time)

        let content = UNMutableNotificationContent()
        content.title = "Shot day"
        content.body = plan.map {
            "Time for your \($0.name) \(RivaFormat.doseNumber($0.currentDoseMg)) mg shot."
        } ?? "Time for your weekly shot."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.reminderID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// The plan's reminder day, else the weekday it started, else Sunday.
    private func resolvedWeekdayName() -> String {
        if let named = RivaWeekday.name(in: plan?.reminderDescription) {
            return named
        }
        if let start = plan?.startDate.flatMap(AccountDates.day) {
            let index = Calendar.current.component(.weekday, from: start)
            return RivaWeekday.names[index - 1]
        }
        return "Sunday"
    }

    private func persist() {
        let calendar = Calendar.current
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: Self.enabledKey)
        defaults.set(calendar.component(.hour, from: time), forKey: Self.hourKey)
        defaults.set(calendar.component(.minute, from: time), forKey: Self.minuteKey)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        NotificationsSheet(account: MockAccountRepository()) {}
    }
}
