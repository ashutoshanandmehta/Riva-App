import SwiftUI

/// Semantic color tokens for the Riva design system.
///
/// Rules:
/// - Feature code must never reference raw hex values or `Color(red:green:blue:)`;
///   always go through a semantic token so a rebrand or dark-mode tweak is a
///   one-file change.
/// - Tokens are named for *role*, not appearance (`textSecondary`, not `gray`).
/// - Every token carries a light and a dark variant.
enum RivaColor {

    // MARK: Brand

    /// Primary brand teal — active states, rings, chart lines, links.
    static let brand = Color(light: 0x1F6D5B, dark: 0x4BB596)
    /// Deeper brand shade — filled buttons, the snap aperture button.
    static let brandDeep = Color(light: 0x235C4F, dark: 0x2F8371)
    /// Soft brand tint — progress-bar tracks, ring tracks.
    static let brandSoft = Color(light: 0xD8EAE2, dark: 0x22322D)
    /// Faint brand wash — tinted stat tiles and icon chips.
    static let brandWash = Color(light: 0xEDF5F1, dark: 0x1A2622)

    // MARK: Landing hero

    /// Gradient stops for the landing page hero background.
    static let heroTop = Color(light: 0x3F9C82, dark: 0x2E7A66)
    static let heroMid = Color(light: 0x27745F, dark: 0x1D5A4A)
    static let heroBottom = Color(light: 0x16493C, dark: 0x0F352C)

    // MARK: Backgrounds & surfaces

    /// App background (light mint-tinted off-white).
    static let background = Color(light: 0xF1F7F3, dark: 0x0C110F)
    /// Card / elevated surface.
    static let surface = Color(light: 0xFFFFFF, dark: 0x171D1A)
    /// High-contrast inverse surface (e.g. the Next Shot card).
    static let surfaceInverse = Color(light: 0x161B19, dark: 0x1F2624)
    /// Neutral chip / badge fill on light surfaces.
    static let fillNeutral = Color(light: 0xEDF1EF, dark: 0x252C29)
    /// Hairline outline for elevated surfaces. Transparent in light mode
    /// (shadows carry the elevation); a faint light stroke in dark mode,
    /// where shadows are invisible against the dark background.
    static let surfaceOutline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.clear
    })

    // MARK: Content

    static let textPrimary = Color(light: 0x101614, dark: 0xF2F5F3)
    static let textSecondary = Color(light: 0x66716C, dark: 0x9BA6A0)
    static let textTertiary = Color(light: 0x93A09A, dark: 0x6E7A74)
    /// Text/icons placed on `brand` or `brandDeep` fills.
    static let textOnBrand = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Primary text on `surfaceInverse`.
    static let textOnInversePrimary = Color(light: 0xF5F8F6, dark: 0xF5F8F6)
    /// Secondary text on `surfaceInverse`.
    static let textOnInverseSecondary = Color(light: 0x9AA8A2, dark: 0x9AA8A2)

    // MARK: On-inverse accents (Next Shot card)

    /// Brand accent tuned for dark surfaces (ring fill, dose pill text).
    static let brandOnInverse = Color(light: 0x5BC4A4, dark: 0x5BC4A4)
    /// Subtle fill on dark surfaces (dose pill background, ring track).
    static let fillOnInverse = Color(light: 0x2A3A34, dark: 0x2A3A34)

    // MARK: Feedback

    static let positive = Color(light: 0x1F6D5B, dark: 0x4BB596)
    static let warning = Color(light: 0xB97B1B, dark: 0xE0A33F)
    static let danger = Color(light: 0xC24A3F, dark: 0xE0705F)
}

// MARK: - Hex helpers (internal to the design system)

extension Color {
    /// Builds a dynamic color from light/dark hex values (0xRRGGBB).
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
