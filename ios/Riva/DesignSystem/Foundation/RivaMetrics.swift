import SwiftUI

/// Spacing scale. Use these instead of magic numbers so density can be tuned
/// centrally.
enum TPCSpacing {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let sm:  CGFloat = 12
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 20
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32

    /// Standard horizontal screen margin.
    static let screenMargin: CGFloat = 22
}

/// Corner radius scale.
enum TPCRadius {
    /// Cards and large surfaces.
    static let card:    CGFloat = 26
    /// Tiles nested inside cards.
    static let tile:    CGFloat = 22
    /// Buttons and pill elements (visually full pill).
    static let control: CGFloat = 999
}

/// Layout constants for app-level chrome (tab bar, FAB).
enum TPCLayout {
    /// Visual height of the floating tab bar (excluding safe area).
    static let tabBarHeight: CGFloat = 64
    /// Bottom content inset so scroll views clear the floating tab bar.
    static let tabBarClearance: CGFloat = 108
    /// Diameter of the floating action button (+ FAB).
    static let fabSize: CGFloat = 46
    /// Diameter of each FAB action button in the expanded fan.
    static let fabActionSize: CGFloat = 44
    /// Distance from the FAB to each action button.
    static let fabFanRadius: CGFloat = 84
}

/// Elevation helpers.
enum TPCShadow {
    /// Soft resting elevation for cards.
    static func card(_ view: some View) -> some View {
        view.shadow(color: Color(hex: 0x1E3325).opacity(0.08), radius: 14, x: 0, y: 6)
    }

    /// Stronger elevation for floating elements (FAB, action buttons).
    static func floating(_ view: some View) -> some View {
        view.shadow(color: Color(hex: 0x1E3325).opacity(0.20), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Legacy aliases (used by existing feature code; removed screen-by-screen)

typealias RivaSpacing = TPCSpacing
typealias RivaRadius  = TPCRadius
typealias RivaLayout  = TPCLayout
typealias RivaShadow  = TPCShadow
