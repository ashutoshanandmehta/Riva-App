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

    /// Landing hero treatment. Flat gold reads as a sticker over a photo, so
    /// there the seal switches to a translucent gradient over `ultraThinMaterial`
    /// with a pale rim, and the monogram picks up its own shadow to stay legible.
    var glass: Bool = false

    var body: some View {
        Text("TPC")
            .font(font ?? .system(size: size * 0.27, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(hex: 0xFBF7EC))
            .shadow(color: TPCColor.heroBackground.opacity(glass ? 0.7 : 0),
                    radius: glass ? 6 : 0)
            .frame(width: size, height: size)
            .background(seal)
            .shadow(color: .black.opacity(shadow ? 0.65 : 0),
                    radius: shadow ? 17 : 0,
                    x: 0,
                    y: shadow ? 16 : 0)
            .accessibilityLabel("The Peptide Company")
    }

    /// The circle behind the monogram.
    @ViewBuilder
    private var seal: some View {
        if glass {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle().fill(
                        RadialGradient(
                            colors: [Color(hex: 0xB08A2E, alpha: 0.70),
                                     Color(hex: 0x10201A, alpha: 0.85)],
                            center: UnitPoint(x: 0.42, y: 0.30),
                            startRadius: 0,
                            endRadius: size * 0.53
                        )
                    )
                }
                .overlay {
                    Circle().strokeBorder(TPCColor.accentPale.opacity(0.5), lineWidth: 1.5)
                }
        } else {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xB08A2E), Color(hex: 0x7E5F14)],
                        center: UnitPoint(x: 0.4, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.5
                    )
                )
                .overlay {
                    Circle().strokeBorder(TPCColor.accentPale.opacity(0.45), lineWidth: 1)
                }
        }
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
