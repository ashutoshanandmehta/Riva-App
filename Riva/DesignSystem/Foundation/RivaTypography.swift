import SwiftUI

/// Typography scale for the Riva design system.
///
/// Feature code should reference these tokens instead of ad-hoc
/// `Font.system(size:)` calls so the type ramp stays consistent and can be
/// re-tuned centrally (e.g. when adopting a custom typeface).
enum RivaFont {
    /// Screen greeting / page titles ("Good morning Sarah").
    static let screenTitle = Font.system(size: 26, weight: .bold)
    /// In-page section headings ("Daily Nutrients").
    static let sectionTitle = Font.system(size: 19, weight: .bold)
    /// Card headings ("Weight Tracking").
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    /// Prominent entity name inside a card ("Tirzepatide").
    static let cardHero = Font.system(size: 22, weight: .bold)

    /// Hero metric ("164.2").
    static let metricXL = Font.system(size: 32, weight: .bold)
    /// Mid-size metric ("-1.2", ring centers).
    static let metricM = Font.system(size: 18, weight: .bold)
    /// Unit that trails a metric ("lbs", "mg in system").
    static let metricUnit = Font.system(size: 14, weight: .semibold)

    static let body = Font.system(size: 15)
    static let footnote = Font.system(size: 13)
    static let captionEmphasized = Font.system(size: 13, weight: .semibold)

    /// Small uppercase labels — badges, tile captions ("THIS WEEK").
    /// Apply through `.rivaOverline(...)` so casing/tracking stay uniform.
    static let overline = Font.system(size: 10.5, weight: .semibold)
    /// Tab bar item labels.
    static let tabLabel = Font.system(size: 10.5, weight: .medium)
}

// MARK: - Overline style

private struct RivaOverlineModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(RivaFont.overline)
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(color)
    }
}

extension View {
    /// Uniform styling for small uppercase labels (badges, tile captions).
    func rivaOverline(_ color: Color = RivaColor.textSecondary) -> some View {
        modifier(RivaOverlineModifier(color: color))
    }
}
