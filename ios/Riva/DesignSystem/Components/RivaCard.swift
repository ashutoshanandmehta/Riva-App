import SwiftUI

/// The standard TPC card container.
///
/// All dashboard modules sit inside a `TPCCard` so surface treatment
/// (radius, padding, elevation) stays uniform and future theming is a
/// one-file change.
struct TPCCard<Content: View>: View {

    enum Style {
        /// Warm white elevated surface (default).
        case standard
        /// High-contrast dark surface (today card, hero cards).
        case inverse
        /// Soft gold-tinted surface (companion prompt, coach note).
        case tinted
    }

    var style: Style = .standard
    @ViewBuilder let content: () -> Content

    var body: some View {
        let card = content()
            .padding(TPCSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )

        switch style {
        case .standard: TPCShadow.card(card)
        case .inverse, .tinted: card
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .standard: TPCColor.surface
        case .inverse:  TPCColor.surfaceInverse
        case .tinted:   TPCColor.brandSoft
        }
    }

    private var borderColor: Color {
        switch style {
        case .standard: TPCColor.surfaceOutline
        case .inverse:  .clear
        case .tinted:   TPCColor.brand.opacity(0.22)
        }
    }
}

typealias RivaCard = TPCCard

#Preview("Card styles") {
    VStack(spacing: TPCSpacing.md) {
        TPCCard {
            Text("Standard card").font(TPCFont.cardTitle)
                .foregroundStyle(TPCColor.textPrimary)
        }
        TPCCard(style: .inverse) {
            Text("Inverse card")
                .font(TPCFont.cardTitle)
                .foregroundStyle(TPCColor.textOnInversePrimary)
        }
        TPCCard(style: .tinted) {
            Text("Tinted card").font(TPCFont.cardTitle)
                .foregroundStyle(TPCColor.textPrimary)
        }
    }
    .padding()
    .background(TPCColor.background)
}
