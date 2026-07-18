import Foundation

/// Quick-log actions revealed by the radial snap menu.
enum SnapAction: String, CaseIterable, Identifiable {
    case weight
    case water
    case food

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "Weight"
        case .water: "Water"
        case .food: "Food"
        }
    }

    var systemImage: String {
        switch self {
        case .weight: "scalemass"
        case .water: "drop"
        case .food: "fork.knife"
        }
    }

    /// Fan-out angle in degrees, measured counter-clockwise from the positive
    /// x-axis, relative to the aperture button.
    var fanAngleDegrees: Double {
        switch self {
        case .weight: 150
        case .water: 90
        case .food: 30
        }
    }
}
