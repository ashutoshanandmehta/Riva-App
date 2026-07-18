import SwiftUI

/// Small uppercase pill badge ("PAST MONTH", "ESTIMATED", "12.5 mg").
struct RivaBadge: View {

    enum Style {
        /// Neutral gray chip on light surfaces.
        case neutral
        /// Brand-tinted chip on light surfaces.
        case brand
        /// Chip tuned for `surfaceInverse` (dose pill on the dark card).
        case onInverse
    }

    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .rivaOverline(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(fill, in: Capsule())
    }

    private var foreground: Color {
        switch style {
        case .neutral: RivaColor.textSecondary
        case .brand: RivaColor.brand
        case .onInverse: RivaColor.brandOnInverse
        }
    }

    private var fill: Color {
        switch style {
        case .neutral: RivaColor.fillNeutral
        case .brand: RivaColor.brandWash
        case .onInverse: RivaColor.fillOnInverse
        }
    }
}

#Preview("Badges") {
    HStack {
        RivaBadge(text: "Past month")
        RivaBadge(text: "Estimated")
        RivaBadge(text: "12.5 mg", style: .onInverse)
            .padding(6)
            .background(RivaColor.surfaceInverse)
    }
    .padding()
}
