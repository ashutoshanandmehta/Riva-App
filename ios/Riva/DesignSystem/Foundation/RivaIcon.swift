import SwiftUI

/// An icon reference that can be either an SF Symbol or a custom SVG-backed
/// template asset from the catalog.
enum TPCIcon: Equatable {
    /// SF Symbol name, e.g. `"house"`.
    case symbol(String)
    /// Asset-catalog image name, e.g. `"MedicationIcon"`.
    case asset(String)
}

/// Renders a `TPCIcon` at an SF-Symbol-comparable optical size, inheriting
/// the current `foregroundStyle` for tinting.
struct TPCIconView: View {
    let icon: TPCIcon
    var pointSize: CGFloat = 19
    var weight: Font.Weight = .regular
    /// Per-icon optical correction — artwork with lots of internal whitespace
    /// can be nudged up to visually match denser glyphs.
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
                .frame(width: (pointSize + 3) * scale, height: (pointSize + 3) * scale)
        }
    }
}

// MARK: - Legacy aliases

typealias RivaIcon     = TPCIcon
typealias RivaIconView = TPCIconView

#Preview {
    HStack(spacing: 20) {
        TPCIconView(icon: .asset("HomeIcon"))
        TPCIconView(icon: .asset("WellnessIcon"))
        TPCIconView(icon: .asset("MedicationIcon"), scale: 1.2)
        TPCIconView(icon: .asset("TrackerIcon"))
        TPCIconView(icon: .symbol("gearshape"))
    }
    .foregroundStyle(TPCColor.brand)
    .padding()
    .background(TPCColor.background)
}
