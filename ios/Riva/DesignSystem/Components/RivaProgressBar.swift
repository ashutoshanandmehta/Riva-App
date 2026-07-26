import SwiftUI

/// Slim rounded progress bar (goal progress, macro bars, medication gauge).
struct TPCProgressBar: View {
    /// Progress in `0...1`; values outside the range are clamped.
    let progress: Double
    var height: CGFloat = 6
    var tint: Color = TPCColor.brand
    var track: Color = TPCColor.surfaceOutline

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }

    private var clamped: Double { min(max(progress, 0), 1) }
}

typealias RivaProgressBar = TPCProgressBar

#Preview {
    VStack(spacing: 16) {
        TPCProgressBar(progress: 0.65)
        TPCProgressBar(progress: 0.74, tint: TPCColor.accentGold)
        TPCProgressBar(progress: 0.45, tint: TPCColor.brandDeep)
    }
    .padding()
    .background(TPCColor.background)
}
