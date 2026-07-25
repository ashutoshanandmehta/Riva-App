import SwiftUI

/// App-wide UI state: tab selection, snap menu visibility, and the shared
/// "coming soon" placeholder sheet.
@MainActor
@Observable
final class AppModel {

    private static let appearanceKey = "riva.appearance"

    var selectedTab: AppTab = .home
    var isSnapMenuOpen = false
    /// Whether the profile screen is presented over the tab content.
    var isProfilePresented = false
    /// Non-nil while a placeholder sheet is presented.
    var activePlaceholder: PlaceholderContext?
    /// Non-nil while the snap scan flow is presented (the value is the
    /// mode the user chose from the radial menu).
    var activeScanMode: ScanMode?
    /// True while the "3D scan (beta)" ARKit volumetric capture flow is
    /// presented. Only ever set true when `CaptureCapability.isSupported`
    /// (the radial menu hides the action otherwise).
    var activeVolumetricScan = false
    /// Non-nil while a quick-log sheet (weight, shot, protein, side
    /// effects, sleep) is presented.
    var activeQuickLog: QuickLog?
    /// Non-nil while an account settings sheet is presented.
    var activeAccountSheet: AccountSheet?
    /// Non-nil while a history or info detail screen is presented.
    var activeDetail: DetailScreen?
    /// Bumped whenever a write (quick-log or accepted scan) lands, so the
    /// always-mounted dashboard tabs know to re-fetch. They observe this and
    /// reload; without it a logged value only appears after a manual refresh.
    private(set) var dashboardRevision = 0
    /// The day's updated totals from the most recent log, so the mounted
    /// dashboards can update instantly before the background refetch lands.
    /// Nil when a write carried no totals (e.g. weight, shots, scans).
    private(set) var pendingTotals: DayTotals?

    /// App-wide appearance, persisted across launches.
    var appearance: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    init() {
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(AppearancePreference.init(rawValue:)) ?? .system
        #if DEBUG
        // UI-test / screenshot hooks: launch with the snap menu open, on a
        // specific tab (`-riva.tab medication`), or with the profile shown.
        if ProcessInfo.processInfo.arguments.contains("-riva.snapMenuOpen") {
            isSnapMenuOpen = true
        }
        if ProcessInfo.processInfo.arguments.contains("-riva.profile") {
            isProfilePresented = true
        }
        if let rawTab = UserDefaults.standard.string(forKey: "riva.tab"),
           let tab = AppTab(rawValue: rawTab) {
            selectedTab = tab
        }
        // Launch straight into the scan flow: `-riva.scan food`
        if let rawMode = UserDefaults.standard.string(forKey: "riva.scan"),
           let mode = ScanMode(rawValue: rawMode) {
            activeScanMode = mode
        }
        // Launch straight into the 3D scan (beta) flow, now that it's real
        // in-app routing rather than the old pre-auth `RivaApp` cover.
        if ProcessInfo.processInfo.arguments.contains("-riva.volumetric") {
            activeVolumetricScan = true
        }
        // Launch straight into a quick-log sheet: `-riva.quickLog shot`
        if let rawLog = UserDefaults.standard.string(forKey: "riva.quickLog"),
           let kind = QuickLog(rawValue: rawLog) {
            activeQuickLog = kind
        }
        // Launch straight into an account sheet: `-riva.accountSheet editGoals`
        if let rawSheet = UserDefaults.standard.string(forKey: "riva.accountSheet"),
           let sheet = AccountSheet(rawValue: rawSheet) {
            activeAccountSheet = sheet
        }
        // Launch straight into a detail screen: `-riva.detail shotHistory`
        if let rawDetail = UserDefaults.standard.string(forKey: "riva.detail"),
           let detail = DetailScreen(rawValue: rawDetail) {
            activeDetail = detail
        }
        #endif
    }

    func select(tab: AppTab) {
        // Bouncy spring so the tab-bar selection pill slides liquidly.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            selectedTab = tab
        }
        closeSnapMenu()
        closeProfile()
    }

    func showProfile() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isProfilePresented = true
        }
    }

    func closeProfile() {
        guard isProfilePresented else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isProfilePresented = false
        }
    }

    func toggleSnapMenu() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isSnapMenuOpen.toggle()
        }
    }

    func closeSnapMenu() {
        guard isSnapMenuOpen else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isSnapMenuOpen = false
        }
    }

    /// Radial menu selection. Food and Water open the live scanner; Weight
    /// opens the quick-log sheet.
    func open(snapAction: SnapAction) {
        closeSnapMenu()
        switch snapAction {
        case .food:
            activeScanMode = .food
        case .water:
            activeScanMode = .water
        case .weight:
            activeQuickLog = .weight
        }
    }

    func present(placeholder: PlaceholderContext) {
        activePlaceholder = placeholder
    }

    /// Signals that logged data changed; mounted dashboards re-fetch.
    func refreshDashboards() {
        dashboardRevision += 1
    }

    /// Applies the totals returned by a log so dashboards can update
    /// optimistically, then bumps the revision to trigger their background
    /// reconcile. `totals` is nil for writes that return none (weight,
    /// shots, scans), which just refetch as before.
    func applyLoggedTotals(_ totals: DayTotals?) {
        pendingTotals = totals
        dashboardRevision += 1
    }
}

/// Describes a not-yet-built feature so every tappable control can respond
/// with a consistent "coming soon" sheet instead of dead silence.
struct PlaceholderContext: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let message: String

    init(id: String, title: String, systemImage: String, message: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    init(for action: SnapAction) {
        switch action {
        case .weight:
            self.init(
                id: "snap.weight",
                title: "Log Weight",
                systemImage: action.systemImage,
                message: "Quick weight logging is coming soon. Your entry will feed the Weight Tracking trend on Home."
            )
        case .water:
            self.init(
                id: "snap.water",
                title: "Log Water",
                systemImage: action.systemImage,
                message: "Water logging is coming soon. Each glass will count toward your daily hydration goal."
            )
        case .food:
            self.init(
                id: "snap.food",
                title: "Scan Food",
                systemImage: action.systemImage,
                message: "The food scanner is coming soon — point your camera at a meal to log calories, protein, and fiber automatically."
            )
        }
    }

    // Common chrome placeholders

    static let logShot = PlaceholderContext(
        id: "medication.logShot",
        title: "Log Today's Shot",
        systemImage: "syringe",
        message: "Shot logging is coming soon. Recording a dose will update your medication-level model and next-shot schedule."
    )

    static let shotDetails = PlaceholderContext(
        id: "medication.shotDetails",
        title: "Shot Details",
        systemImage: "calendar",
        message: "Dose details and schedule management are coming soon."
    )

    static let medicationCurveInfo = PlaceholderContext(
        id: "medication.curveInfo",
        title: "Medication Curve",
        systemImage: "info.circle",
        message: "The curve estimates your GLP-1 concentration from your dose history. A detailed explanation of the model is coming soon."
    )

    static let logProtein = PlaceholderContext(
        id: "tracker.logProtein",
        title: "Log Protein",
        systemImage: "fork.knife",
        message: "Quick protein logging is coming soon. Logged meals will count toward your daily protein goal."
    )

    static let weightDetails = PlaceholderContext(
        id: "tracker.weightDetails",
        title: "Weight Details",
        systemImage: "scalemass",
        message: "Detailed weight history and unit preferences are coming soon."
    )

    static let sideEffects = PlaceholderContext(
        id: "tracker.sideEffects",
        title: "Side Effects",
        systemImage: "figure.stand",
        message: "Body-map side-effect logging is coming soon. Reported symptoms will be shared with your care team."
    )

    static let logSideEffect = PlaceholderContext(
        id: "tracker.logSideEffect",
        title: "Log Side Effect",
        systemImage: "exclamationmark.bubble",
        message: "Quick symptom logging is coming soon. Tracking side effects helps Riva time your doses and coaching."
    )

    static let logSleep = PlaceholderContext(
        id: "tracker.logSleep",
        title: "Log Sleep",
        systemImage: "moon.zzz",
        message: "Sleep logging is coming soon — including automatic import from Apple Health."
    )

    // Profile placeholders

    static let editProfile = PlaceholderContext(
        id: "profile.edit",
        title: "Edit Profile",
        systemImage: "pencil",
        message: "Editing your name, photo, and contact details is coming soon."
    )

    static let editGoals = PlaceholderContext(
        id: "profile.editGoals",
        title: "Edit Goals",
        systemImage: "flag",
        message: "Adjusting your weight goals and daily targets is coming soon — changes will sync with your care team."
    )

    static let doseSettings = PlaceholderContext(
        id: "profile.dose",
        title: "Dose Settings",
        systemImage: "syringe",
        message: "Dose management is coming soon. Dose changes are made together with your prescriber."
    )

    static let injectionDaySettings = PlaceholderContext(
        id: "profile.injectionDay",
        title: "Injection Day",
        systemImage: "calendar",
        message: "Changing your weekly injection day is coming soon."
    )

    static let siteRotationSettings = PlaceholderContext(
        id: "profile.siteRotation",
        title: "Site Rotation",
        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
        message: "Injection-site rotation preferences are coming soon."
    )

    static let notifications = PlaceholderContext(
        id: "profile.notifications",
        title: "Notifications",
        systemImage: "bell",
        message: "Shot reminders, hydration nudges, and coaching notification preferences are coming soon."
    )

    static let privacySecurity = PlaceholderContext(
        id: "profile.privacy",
        title: "Privacy & Security",
        systemImage: "lock",
        message: "Data controls, export, and security settings are coming soon."
    )

    static let logOut = PlaceholderContext(
        id: "profile.logOut",
        title: "Log Out",
        systemImage: "rectangle.portrait.and.arrow.right",
        message: "Account sign-out arrives with the authentication flow."
    )

}
