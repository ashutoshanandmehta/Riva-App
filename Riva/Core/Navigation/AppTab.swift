import Foundation

/// Bottom navigation destinations (excluding the central snap button, which is
/// an action, not a tab).
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case wellness
    case medication
    case tracker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .wellness: "Wellness"
        case .medication: "Medication"
        case .tracker: "Tracker"
        }
    }

    /// Tab icon — one custom brand SVG per tab, identical in both selection
    /// states. Selection is communicated by tint and the sliding pill only,
    /// so icons never shift shape or weight when tapped.
    var icon: RivaIcon {
        switch self {
        case .home: .asset("HomeIcon")
        case .wellness: .asset("WellnessIcon")
        case .medication: .asset("MedicationIcon")
        case .tracker: .asset("TrackerIcon")
        }
    }

    /// Optical size correction for this tab's icon (see `RivaIconView.scale`).
    var iconScale: CGFloat {
        switch self {
        case .home: 1.25
        case .wellness: 1.15
        case .medication: 1.2
        case .tracker: 1
        }
    }

    /// Tabs rendered to the left of the snap button.
    static let leading: [AppTab] = [.home, .wellness]
    /// Tabs rendered to the right of the snap button.
    static let trailing: [AppTab] = [.medication, .tracker]
}
