import SwiftUI

/// Small uppercase pill badge ("PAST MONTH", "ESTIMATED", "12.5 mg").
struct TPCBadge: View {

    enum Style {
        /// Neutral fill on light surfaces.
        case neutral
        /// Gold-tinted chip on light surfaces.
        case brand
        /// Chip tuned for inverse (dark card) surfaces.
        case onInverse
    }

    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .tpcOverline(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(fill, in: Capsule())
    }

    private var foreground: Color {
        switch style {
        case .neutral:   TPCColor.textSecondary
        case .brand:     TPCColor.brand
        case .onInverse: TPCColor.accentPale
        }
    }

    private var fill: Color {
        switch style {
        case .neutral:   TPCColor.fillNeutral
        case .brand:     TPCColor.brandSoft
        case .onInverse: TPCColor.fillOnInverse
        }
    }
}

// Legacy alias
typealias RivaBadge = TPCBadge

#Preview("Badges") {
    HStack {
        TPCBadge(text: "Past month")
        TPCBadge(text: "Estimated", style: .brand)
        TPCBadge(text: "12.5 mg", style: .onInverse)
            .padding(6)
            .background(TPCColor.surfaceInverse)
    }
    .padding()
    .background(TPCColor.background)
}
