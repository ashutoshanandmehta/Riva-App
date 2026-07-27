import SwiftUI

/// The TPC brand mark: a gold seal with the cream "TPC" monogram. Single source
/// of truth for the logo — `BrandTopBar`, `LandingView` and `LoginView` all
/// render this rather than redrawing the circle.
///
/// The monogram scales with the seal so the mark keeps its proportions at any
/// size; `font` overrides the face where a screen needs the brand grotesque
/// instead of the system default.
struct TPCSeal: View {
    var size: CGFloat = 30
    var font: Font?

    /// Shadow is opt-in: only screens that place the seal over imagery need it.
    var shadow: Bool = false

    var body: some View {
        Text("TPC")
            .font(font ?? .system(size: size * 0.27, weight: .heavy))
            .foregroundStyle(Color(hex: 0xFBF7EC))
            .frame(width: size, height: size)
            .background(
                RadialGradient(
                    colors: [Color(hex: 0xB08A2E), Color(hex: 0x7E5F14)],
                    center: UnitPoint(x: 0.4, y: 0.3),
                    startRadius: 0,
                    endRadius: size * 0.5
                ),
                in: Circle()
            )
            .shadow(color: .black.opacity(shadow ? 0.65 : 0),
                    radius: shadow ? 17 : 0,
                    x: 0,
                    y: shadow ? 16 : 0)
            .accessibilityLabel("The Peptide Company")
    }
}

#Preview {
    VStack(spacing: TPCSpacing.lg) {
        TPCSeal()
        TPCSeal(size: 64)
        TPCSeal(size: 104,
                font: Font.custom("Bricolage Grotesque", fixedSize: 21).weight(.heavy),
                shadow: true)
    }
    .padding()
    .background(TPCColor.background)
}
