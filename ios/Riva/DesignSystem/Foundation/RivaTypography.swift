import SwiftUI

/// Typography scale for the TPC design system.
///
/// Display tokens use Bricolage Grotesque; body tokens use DM Sans.
/// Cormorant Garamond is reserved for the landing screen only.
///
/// IMPORTANT — font files must be added to the Xcode project and declared in
/// Info.plist under UIAppFonts before these render correctly. Until the files
/// are bundled the system falls back to SF Pro silently.
///
/// Required font files:
///   BricolageGrotesque-Bold.ttf        (weight 700)
///   BricolageGrotesque-ExtraBold.ttf   (weight 800)
///   DMSans-Medium.ttf                  (weight 500)
///   DMSans-Bold.ttf                    (weight 700)
///   CormorantGaramond-Regular.ttf
///   CormorantGaramond-Italic.ttf
enum TPCFont {

    // MARK: Display — Bricolage Grotesque (variable font, one file covers all weights)

    /// Screen greeting / page titles ("Hey Alex — how's today going?").
    static let screenTitle  = Font.custom(Family.display, size: 18).weight(.bold)
    /// In-page section headings ("Today's plan", "Weight tracking").
    static let sectionTitle = Font.custom(Family.display, size: 21).weight(.bold)
    /// Card headings and action titles.
    static let cardTitle    = Font.custom(Family.display, size: 20).weight(.bold)
    /// Prominent entity name inside a card ("Tirzepatide 0.5 mg").
    static let cardHero     = Font.custom(Family.display, size: 22).weight(.bold)
    /// Hero metric — the largest number on screen ("3 / 4", "182.4").
    static let metricXL     = Font.custom(Family.display, size: 34).weight(.heavy)
    /// Mid-size metric — calorie totals, weight stat values.
    static let metricL      = Font.custom(Family.display, size: 24).weight(.bold)
    /// Compact metric — next-shot day, mini stat tiles.
    static let metricM      = Font.custom(Family.display, size: 19).weight(.bold)
    /// Streak badge and small badge numbers.
    static let metricS      = Font.custom(Family.display, size: 12).weight(.heavy)

    // MARK: Body — DM Sans (variable font, one file covers all weights)

    /// Standard body copy.
    static let body              = Font.custom(Family.body, size: 15).weight(.medium)
    /// Emphasized body (habit labels, card row titles).
    static let bodyBold          = Font.custom(Family.body, size: 15).weight(.bold)
    /// Footnote / supporting detail.
    static let footnote          = Font.custom(Family.body, size: 13).weight(.medium)
    /// Emphasized footnote.
    static let captionEmphasized = Font.custom(Family.body, size: 13).weight(.bold)
    /// Small caption (sub-labels, secondary detail).
    static let caption           = Font.custom(Family.body, size: 12).weight(.medium)
    /// Overline — applied via `.tpcOverline(...)` which adds casing + tracking.
    static let overline          = Font.custom(Family.body, size: 9.5).weight(.bold)
    /// Tab bar item labels.
    static let tabLabel          = Font.custom(Family.body, size: 10.5).weight(.bold)
    /// Unit label trailing a metric ("lbs", "kcal").
    static let metricUnit        = Font.custom(Family.body, size: 13).weight(.medium)

    // MARK: Serif — Cormorant Garamond (variable font, landing screen only)

    static let serifHero       = Font.custom(Family.serif, size: 44).weight(.medium)
    static let serifHeroItalic = Font.custom(Family.serif, size: 33).italic()

    // MARK: Preferred family names from variable font metadata

    enum Family {
        static let display = "Bricolage Grotesque"
        static let body    = "DM Sans"
        static let serif   = "Cormorant Garamond"
    }
}

// MARK: - Overline style

private struct TPCOverlineModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(TPCFont.overline)
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundStyle(color)
    }
}

extension View {
    /// Uniform styling for small uppercase labels (badges, tile captions, flag strips).
    func tpcOverline(_ color: Color = TPCColor.textTertiary) -> some View {
        modifier(TPCOverlineModifier(color: color))
    }

    // Legacy alias kept until all call sites are updated in later steps.
    func rivaOverline(_ color: Color = TPCColor.textTertiary) -> some View {
        tpcOverline(color)
    }
}
