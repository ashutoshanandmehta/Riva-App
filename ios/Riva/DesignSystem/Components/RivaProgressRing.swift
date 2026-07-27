import SwiftUI

/// Circular progress ring with arbitrary center content
/// (calorie ring, nutrient rings, next-shot countdown).
struct TPCProgressRing<Center: View>: View {
    /// Progress in `0...1`; values outside the range are clamped.
    let progress: Double
    var size: CGFloat = 68
    var lineWidth: CGFloat = 6
    var tint: Color = TPCColor.brand
    var track: Color = TPCColor.surfaceOutline
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }

    private var clamped: Double { min(max(progress, 0), 1) }
}

typealias RivaProgressRing = TPCProgressRing

#Preview {
    HStack(spacing: 24) {
        TPCProgressRing(progress: 0.71, size: 92, lineWidth: 8) {
            VStack(spacing: 1) {
                Text("470").font(TPCFont.metricM).foregroundStyle(TPCColor.textPrimary)
                Text("LEFT").font(TPCFont.overline).foregroundStyle(TPCColor.textTertiary)
            }
        }
        TPCProgressRing(
            progress: 0.74,
            tint: TPCColor.accentGold,
            track: TPCColor.fillOnInverse
        ) {
            Text("2d").font(TPCFont.metricM).foregroundStyle(TPCColor.textOnInversePrimary)
        }
        .padding(8)
        .background(TPCColor.surfaceInverse, in: Circle())
    }
    .padding()
    .background(TPCColor.background)
}
