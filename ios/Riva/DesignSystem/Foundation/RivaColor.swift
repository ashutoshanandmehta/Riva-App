import SwiftUI
import UIKit

/// Semantic color tokens for the TPC design system.
///
/// Rules:
/// - Feature code must never reference raw hex values; always go through a
///   semantic token so a rebrand or dark-mode tweak is a one-file change.
/// - Tokens are named for *role*, not appearance (`textSecondary`, not `gray`).
/// - Every token resolves against the active colour scheme. Where a role is
///   the same in both — gold, or text that only ever sits on a dark surface —
///   the two values are deliberately equal rather than absent, so adding a
///   dark variant later stays a one-line edit.
enum TPCColor {

    // MARK: Brand

    /// Primary gold — buttons, active states, links. Lifted in dark so it
    /// clears the near-black background at the same contrast it has on cream.
    static let brand = Color(light: 0x9A7526, dark: 0xB08A2E)
    /// Hover / pressed gold.
    static let brandHover = Color(light: 0xB08A2E, dark: 0xC8A454)
    /// Forest green — dark filled buttons and inverse surfaces. In dark it
    /// lifts off the background, which is darker than this green would be.
    static let brandDeep = Color(light: 0x1E3325, dark: 0x2A4A34)
    /// Mid forest green — dark card gradient, hero card bg.
    static let brandMid = Color(light: 0x24402D, dark: 0x2F543B)
    /// Gold tint fill — icon chip backgrounds, expandable rows.
    static let brandSoft = Color(light: 0x9A7526, dark: 0xC8A454, lightAlpha: 0.10, darkAlpha: 0.18)
    /// Very faint gold wash — subtle tinted tiles.
    static let brandWash = Color(light: 0x9A7526, dark: 0xC8A454, lightAlpha: 0.06, darkAlpha: 0.12)

    // MARK: Accent gold scale

    /// Light gold — progress bar fills, macro bars, weight chart line.
    static let accentGold = Color(light: 0xC8A454, dark: 0xC8A454)
    /// Pale gold — text and borders on inverse (dark) surfaces.
    static let accentPale = Color(light: 0xE7D9A9, dark: 0xE7D9A9)
    /// Deep gold — links, overline text. Inverts to pale gold in dark, where
    /// the deep tone reads as unreadable brown.
    static let accentLink = Color(light: 0x8C6A18, dark: 0xD9B45E)

    // MARK: Backgrounds & surfaces

    /// App background — warm cream, or a warm green-black in dark.
    static let background = Color(light: 0xF6F2E8, dark: 0x0F1512)
    /// Card / elevated surface.
    static let surface = Color(light: 0xFFFDF7, dark: 0x19201B)
    /// Further elevated surface (option rows inside expandable cards).
    static let surfaceElevated = Color(light: 0xFBF7EC, dark: 0x212A23)
    /// High-contrast feature surface — dark cards, today hero card. Stays
    /// green in both schemes: flipping it to cream in dark would put a
    /// spotlight on the one card meant to sit *behind* the content.
    static let surfaceInverse = Color(light: 0x1E3325, dark: 0x2A4A34)
    /// Neutral fill on standard surfaces — text field and chip backgrounds.
    static let fillNeutral = Color(light: 0x1E3325, dark: 0xF6F2E8, lightAlpha: 0.07, darkAlpha: 0.08)
    /// Subtle fill on inverse (dark) surfaces.
    static let fillOnInverse = Color(light: 0xF6F2E8, dark: 0xF6F2E8, lightAlpha: 0.10, darkAlpha: 0.14)
    /// Hairline border for cards and rows. Ink in light, cream in dark — a
    /// dark hairline on a dark surface is no border at all.
    static let surfaceOutline = Color(light: 0x1E3325, dark: 0xF6F2E8, lightAlpha: 0.10, darkAlpha: 0.14)

    // MARK: Content

    static let textPrimary = Color(light: 0x17201B, dark: 0xF1EDE3)
    static let textSecondary = Color(light: 0x5C6259, dark: 0xB4BAB0)
    static let textTertiary = Color(light: 0x8B9189, dark: 0x8B9189)
    static let textFaint = Color(light: 0xA3AAA4, dark: 0x787E77)
    /// Text/icons on gold-filled elements (primary buttons).
    static let textOnBrand = Color(light: 0xFBF7EC, dark: 0xFBF7EC)
    /// Primary text on inverse (dark) surfaces.
    static let textOnInversePrimary = Color(light: 0xF6F2E8, dark: 0xF6F2E8)
    /// Secondary text on inverse (dark) surfaces.
    static let textOnInverseSecondary = Color(
        light: 0xF6F2E8, dark: 0xF6F2E8, lightAlpha: 0.66, darkAlpha: 0.66
    )

    // MARK: On-inverse accents

    /// Gold accent tuned for dark surfaces (ring fills, stat highlights).
    static let brandOnInverse = Color(light: 0xC8A454, dark: 0xC8A454)

    // MARK: Landing

    /// Landing screen dark background. The landing art is dark in both
    /// schemes, so this and the hero aliases below are deliberately fixed.
    static let heroBackground = Color(hex: 0x10201A)

    // MARK: Feedback

    static let positive = Color(light: 0x3E6349, dark: 0x6FA07E)
    static let warning = Color(light: 0xC8A454, dark: 0xC8A454)
    static let danger = Color(light: 0xA5391F, dark: 0xE07A62)

    // MARK: Macros

    /// Macro bar fills on the Home calories card — one token per macro so the
    /// card never picks a colour by matching on a nutrient's name. Protein
    /// carries its own dark value rather than aliasing `brandDeep`: a bar has
    /// to read against the card, not merely differ from the background.
    static let macroProtein = Color(light: 0x1E3325, dark: 0x7FA98C)
    static let macroCarbs = accentGold
    static let macroFiber = danger

    // MARK: Wellness (kept for WellnessView until redesigned)

    static let heroCard = surfaceInverse
    static let fillOnHero = Color(light: 0xF6F2E8, dark: 0xF6F2E8)
    static let textOnHeroFill = Color(light: 0x1E3325, dark: 0x1E3325)
    static let wellnessAccent = Color(light: 0xC8A454, dark: 0xC8A454)

    // MARK: Legacy landing aliases (removed when LandingView is rebuilt in step 2)

    static let heroTop = Color(hex: 0x24402D)
    static let heroMid = Color(hex: 0x1E3325)
    static let heroBottom = Color(hex: 0x10201A)
}

// MARK: - Hex helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// A token that resolves against the active colour scheme, including the
    /// user's override in Profile — `.preferredColorScheme` sets the trait
    /// these read, so an app forced to Dark on a light device still resolves
    /// the dark value.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    fileprivate convenience init(hex: UInt32, alpha: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
