import SwiftUI

/// Semantic color tokens for the TPC design system.
///
/// Rules:
/// - Feature code must never reference raw hex values; always go through a
///   semantic token so a rebrand or dark-mode tweak is a one-file change.
/// - Tokens are named for *role*, not appearance (`textSecondary`, not `gray`).
enum TPCColor {

    // MARK: Brand

    /// Primary gold — buttons, active states, links.
    static let brand = Color(hex: 0x9A7526)
    /// Hover / pressed gold.
    static let brandHover = Color(hex: 0xB08A2E)
    /// Forest green — dark filled buttons and inverse surfaces.
    static let brandDeep = Color(hex: 0x1E3325)
    /// Mid forest green — dark card gradient, hero card bg.
    static let brandMid = Color(hex: 0x24402D)
    /// Gold tint fill — icon chip backgrounds, expandable rows.
    static let brandSoft = Color(hex: 0x9A7526, alpha: 0.10)
    /// Very faint gold wash — subtle tinted tiles.
    static let brandWash = Color(hex: 0x9A7526, alpha: 0.06)

    // MARK: Accent gold scale

    /// Light gold — progress bar fills, macro bars, weight chart line.
    static let accentGold = Color(hex: 0xC8A454)
    /// Pale gold — text and borders on inverse (dark) surfaces.
    static let accentPale = Color(hex: 0xE7D9A9)
    /// Deep gold — links, overline text on cream.
    static let accentLink = Color(hex: 0x8C6A18)

    // MARK: Backgrounds & surfaces

    /// App background — warm cream.
    static let background = Color(hex: 0xF6F2E8)
    /// Card / elevated surface.
    static let surface = Color(hex: 0xFFFDF7)
    /// Further elevated surface (option rows inside expandable cards).
    static let surfaceElevated = Color(hex: 0xFBF7EC)
    /// High-contrast inverse surface — dark cards, today hero card.
    static let surfaceInverse = Color(hex: 0x1E3325)
    /// Neutral fill on light surfaces.
    static let fillNeutral = Color(hex: 0x1E3325, alpha: 0.07)
    /// Subtle fill on inverse (dark) surfaces.
    static let fillOnInverse = Color(hex: 0xF6F2E8, alpha: 0.10)
    /// Hairline border for cards and rows.
    static let surfaceOutline = Color(hex: 0x1E3325, alpha: 0.10)

    // MARK: Content

    static let textPrimary = Color(hex: 0x17201B)
    static let textSecondary = Color(hex: 0x5C6259)
    static let textTertiary = Color(hex: 0x8B9189)
    static let textFaint = Color(hex: 0xA3AAA4)
    /// Text/icons on gold-filled elements (primary buttons).
    static let textOnBrand = Color(hex: 0xFBF7EC)
    /// Primary text on inverse (dark) surfaces.
    static let textOnInversePrimary = Color(hex: 0xF6F2E8)
    /// Secondary text on inverse (dark) surfaces.
    static let textOnInverseSecondary = Color(hex: 0xF6F2E8, alpha: 0.66)

    // MARK: On-inverse accents

    /// Gold accent tuned for dark surfaces (ring fills, stat highlights).
    static let brandOnInverse = Color(hex: 0xC8A454)

    // MARK: Landing

    /// Landing screen dark background.
    static let heroBackground = Color(hex: 0x10201A)

    // MARK: Feedback

    static let positive = Color(hex: 0x3E6349)
    static let warning = Color(hex: 0xC8A454)
    static let danger = Color(hex: 0xA5391F)

    // MARK: Macros

    /// Macro bar fills on the Home calories card — one token per macro so the
    /// card never picks a colour by matching on a nutrient's name.
    static let macroProtein = brandDeep
    static let macroCarbs = accentGold
    static let macroFiber = danger

    // MARK: Wellness (kept for WellnessView until redesigned)

    static let heroCard = surfaceInverse
    static let fillOnHero = Color(hex: 0xF6F2E8)
    static let textOnHeroFill = Color(hex: 0x1E3325)
    static let wellnessAccent = Color(hex: 0xC8A454)

    // MARK: Legacy landing aliases (removed when LandingView is rebuilt in step 2)

    static let heroTop = Color(hex: 0x24402D)
    static let heroMid = Color(hex: 0x1E3325)
    static let heroBottom = Color(hex: 0x10201A)
}

// MARK: - Hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
