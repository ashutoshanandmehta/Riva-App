import SwiftUI

/// The standard Riva card container.
///
/// All dashboard modules sit inside a `RivaCard` so surface treatment
/// (radius, padding, elevation) stays uniform and future theming is a
/// one-file change.
struct RivaCard<Content: View>: View {

    enum Style {
        /// White elevated surface (default).
        case standard
        /// High-contrast dark surface (e.g. Next Shot).
        case inverse
        /// Soft brand-tinted surface, no elevation (e.g. Riva Intelligence).
        case tinted
    }

    var style: Style = .standard
    @ViewBuilder let content: () -> Content

    var body: some View {
        let card = content()
            .padding(RivaSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous)
            )
            .rivaSurfaceOutline(cornerRadius: RivaRadius.card)

        switch style {
        case .standard: RivaShadow.card(card)
        case .inverse, .tinted: card
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .standard: RivaColor.surface
        case .inverse: RivaColor.surfaceInverse
        case .tinted: RivaColor.brandWash
        }
    }
}

#Preview("Card styles") {
    VStack(spacing: RivaSpacing.md) {
        RivaCard {
            Text("Standard card").font(RivaFont.cardTitle)
        }
        RivaCard(style: .inverse) {
            Text("Inverse card")
                .font(RivaFont.cardTitle)
                .foregroundStyle(RivaColor.textOnInversePrimary)
        }
    }
    .padding()
    .background(RivaColor.background)
}
