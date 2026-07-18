import SwiftUI

/// An icon reference that can be either an SF Symbol or a custom SVG-backed
/// template asset from the catalog.
///
/// Custom brand icons (SVG in `Assets.xcassets`, template rendering, vector
/// data preserved) and system symbols render through `RivaIconView` so both
/// kinds tint and scale uniformly.
enum RivaIcon: Equatable {
    /// SF Symbol name, e.g. `"house"`.
    case symbol(String)
    /// Asset-catalog image name, e.g. `"MedicationIcon"`.
    case asset(String)
}

/// Renders a `RivaIcon` at an SF-Symbol-comparable optical size, inheriting
/// the current `foregroundStyle` for tinting.
struct RivaIconView: View {
    let icon: RivaIcon
    /// Point size the icon should optically match (SF Symbol font size).
    var pointSize: CGFloat = 19
    var weight: Font.Weight = .regular
    /// Per-icon optical correction — artwork with lots of internal whitespace
    /// (e.g. the two-object Medication icon) can be nudged up to visually
    /// match denser glyphs.
    var scale: CGFloat = 1

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: pointSize * scale, weight: weight))
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                // Full-frame vector art reads slightly smaller than a glyph
                // of the same point size; pad it up to match optically.
                .frame(width: (pointSize + 3) * scale, height: (pointSize + 3) * scale)
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        RivaIconView(icon: .asset("HomeIcon"))
        RivaIconView(icon: .asset("WellnessIcon"))
        RivaIconView(icon: .asset("MedicationIcon"), scale: 1.2)
        RivaIconView(icon: .asset("TrackerIcon"))
        RivaIconView(icon: .symbol("gearshape"))
    }
    .foregroundStyle(RivaColor.brand)
    .padding()
}
