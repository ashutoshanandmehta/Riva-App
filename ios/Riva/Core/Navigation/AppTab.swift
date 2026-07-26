import Foundation

/// Bottom navigation destinations — 5 tabs, no central action button.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case wellness
    case companion
    case medication
    case tracker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:       "Home"
        case .wellness:   "Wellness"
        case .companion:  "AI companion"
        case .medication: "Meds"
        case .tracker:    "Tracker"
        }
    }

    var icon: RivaIcon {
        switch self {
        case .home:       .asset("HomeIcon")
        case .wellness:   .asset("WellnessIcon")
        case .companion:  .symbol("sparkles")
        case .medication: .asset("MedicationIcon")
        case .tracker:    .asset("TrackerIcon")
        }
    }

    var iconScale: CGFloat {
        switch self {
        case .home:       1.25
        case .wellness:   1.15
        case .companion:  1.0
        case .medication: 1.2
        case .tracker:    1.0
        }
    }

    /// Legacy split kept for backward compatibility — no longer used by the tab bar.
    static let leading: [AppTab]  = [.home, .wellness]
    static let trailing: [AppTab] = [.medication, .tracker]
}
