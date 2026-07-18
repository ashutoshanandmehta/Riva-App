import SwiftUI

/// Circular progress ring with arbitrary center content
/// (nutrient rings, next-shot countdown).
struct RivaProgressRing<Center: View>: View {
    /// Progress in `0...1`; values outside the range are clamped.
    let progress: Double
    var size: CGFloat = 68
    var lineWidth: CGFloat = 6
    var tint: Color = RivaColor.brand
    var track: Color = RivaColor.brandSoft
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

#Preview {
    HStack(spacing: 24) {
        RivaProgressRing(progress: 0.86) {
            Text("95g").font(RivaFont.metricM)
        }
        RivaProgressRing(
            progress: 0.71,
            tint: RivaColor.brandOnInverse,
            track: RivaColor.fillOnInverse
        ) {
            VStack(spacing: 0) {
                Text("2d").font(RivaFont.metricM).foregroundStyle(.white)
                Text("left").font(.system(size: 10)).foregroundStyle(RivaColor.textOnInverseSecondary)
            }
        }
        .padding(8)
        .background(RivaColor.surfaceInverse, in: Circle())
    }
    .padding()
}
