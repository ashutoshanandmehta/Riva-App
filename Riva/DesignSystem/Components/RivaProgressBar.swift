import SwiftUI

/// Slim rounded progress bar (goal progress, medication level gauge).
struct RivaProgressBar: View {
    /// Progress in `0...1`; values outside the range are clamped.
    let progress: Double
    var height: CGFloat = 8
    var tint: Color = RivaColor.brand
    var track: Color = RivaColor.brandSoft

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

#Preview {
    VStack(spacing: 16) {
        RivaProgressBar(progress: 0.65)
        RivaProgressBar(progress: 0.45, height: 6)
    }
    .padding()
}
