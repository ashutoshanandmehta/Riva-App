import SwiftUI

/// Strip of rounded daily-weight bars whose height tracks each day's value
/// and whose tint deepens toward today (rightmost = today, full brand).
/// Shared by the Tracker dashboard and the Weekly Summary.
struct WeightBarsStrip: View {
    /// Daily weights, oldest first.
    let dailyLbs: [Double]
    var barHeight: CGFloat = 56

    var body: some View {
        let minW = dailyLbs.min() ?? 0
        let maxW = dailyLbs.max() ?? 1
        let span = max(maxW - minW, 0.1)

        HStack(alignment: .bottom, spacing: RivaSpacing.xs) {
            ForEach(Array(dailyLbs.enumerated()), id: \.offset) { index, weight in
                let normalized = 0.62 + 0.38 * ((weight - minW) / span)
                let isToday = index == dailyLbs.count - 1
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(barColor(index: index, isToday: isToday))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight * normalized)
            }
        }
        .frame(height: barHeight, alignment: .bottom)
        .accessibilityLabel("Daily weight, past \(dailyLbs.count) days")
    }

    private func barColor(index: Int, isToday: Bool) -> Color {
        if isToday { return RivaColor.brand }
        // Older days fade toward the soft tint.
        let position = Double(index) / Double(max(dailyLbs.count - 1, 1))
        return RivaColor.brandSoft.opacity(0.55 + 0.45 * position)
    }
}

#Preview {
    WeightBarsStrip(dailyLbs: [185.4, 185.8, 185.1, 185.3, 184.9, 185.0, 184.2])
        .padding()
        .background(RivaColor.surface)
}
