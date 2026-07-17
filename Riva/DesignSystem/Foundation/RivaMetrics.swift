import SwiftUI

/// Spacing scale. Use these instead of magic numbers so density can be tuned
/// centrally.
enum RivaSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Standard horizontal screen margin.
    static let screenMargin: CGFloat = 20
}

/// Corner radius scale.
enum RivaRadius {
    /// Cards and other large surfaces.
    static let card: CGFloat = 24
    /// Tiles nested inside cards.
    static let tile: CGFloat = 16
    /// Buttons.
    static let control: CGFloat = 18
}

/// Layout constants for app-level chrome (tab bar, snap menu).
enum RivaLayout {
    /// Visual height of the floating tab bar (excluding safe area).
    static let tabBarHeight: CGFloat = 64
    /// Bottom content inset so scroll views clear the floating tab bar.
    static let tabBarClearance: CGFloat = 108
    /// Diameter of the central snap (aperture) button.
    static let snapButtonSize: CGFloat = 58
    /// Diameter of each radial snap action button.
    static let snapActionSize: CGFloat = 56
    /// Distance from the aperture button to each radial action.
    static let snapFanRadius: CGFloat = 96
}

/// Elevation styles.
enum RivaShadow {
    /// Soft resting elevation for cards.
    static func card(_ view: some View) -> some View {
        view.shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    /// Slightly stronger elevation for floating elements (fan buttons).
    static func floating(_ view: some View) -> some View {
        view.shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }
}
