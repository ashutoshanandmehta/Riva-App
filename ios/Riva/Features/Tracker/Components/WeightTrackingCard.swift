import Charts
import SwiftUI

/// Weight Tracking card: monthly trend chart plus weekly and total deltas.
/// Leads the Tracker tab. Journey progress toward the target weight lives on
/// Home, so it is deliberately absent here.
struct WeightTrackingCard: View {
    let summary: WeightSummary
    let onDetails: () -> Void

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                header
                chart
                statTiles
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: TPCSpacing.xs) {
            RivaIconChip(systemImage: "chart.xyaxis.line")
            Text("Weight Tracking")
                .font(TPCFont.cardTitle)
                .foregroundStyle(TPCColor.textPrimary)
            Spacer()
            RivaBadge(text: "Past month")
            HistoryChevronButton(accessibilityLabel: "Weight history", action: onDetails)
        }
    }

    // MARK: Chart

    private var chart: some View {
        Chart(summary.history) { entry in
            LineMark(
                x: .value("Date", entry.date),
                y: .value("Weight", entry.weightLbs)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .foregroundStyle(TPCColor.brand)

            // A line needs two points. With a single weigh-in — every new
            // account, and this is the Tracker's lead card — the plot would
            // otherwise be an empty grid, so draw the one reading as a dot.
            if summary.history.count < 2 {
                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weightLbs)
                )
                .symbolSize(80)
                .foregroundStyle(TPCColor.brand)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                let date = value.as(Date.self)
                // Anchor the final label ("Today") to its trailing edge so it
                // isn't clipped by the plot boundary; others use the default.
                AxisValueLabel(anchor: date == xAxisDates.last ? .topTrailing : nil) {
                    if let date {
                        Text(label(for: date))
                            .font(.system(size: 10))
                            .foregroundStyle(TPCColor.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                    .foregroundStyle(TPCColor.brandSoft.opacity(0.8))
                AxisValueLabel()
                    .font(.system(size: 10))
                    .foregroundStyle(TPCColor.textTertiary)
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Weight trend over the past month")
    }

    private var yDomain: ClosedRange<Double> {
        let weights = summary.history.map(\.weightLbs)
        guard let min = weights.min(), let max = weights.max() else { return 100...200 }
        return (min - 3)...(max + 3)
    }

    /// Three reference points: a month ago, two weeks ago, today.
    private var xAxisDates: [Date] {
        guard let first = summary.history.first?.date,
              let last = summary.history.last?.date else { return [] }
        let mid = first.addingTimeInterval(last.timeIntervalSince(first) / 2)
        return [first, mid, last]
    }

    private func label(for date: Date) -> String {
        guard let last = summary.history.last?.date else { return "" }
        let days = Calendar.current.dateComponents([.day], from: date, to: last).day ?? 0
        switch days {
        case 0: return "Today"
        case ..<10: return "\(days)d ago"
        default: return "\(Int((Double(days) / 7).rounded()))w ago"
        }
    }

    // MARK: Stats

    private var statTiles: some View {
        HStack(spacing: TPCSpacing.sm) {
            RivaStatTile(
                caption: "This week",
                systemImage: summary.weeklyChangeLbs <= 0 ? "arrow.down" : "arrow.up",
                value: RivaFormat.signedDelta(summary.weeklyChangeLbs),
                unit: "lbs"
            )
            RivaStatTile(
                caption: "Total loss",
                systemImage: "arrow.down.circle",
                value: RivaFormat.signedDelta(summary.totalChangeLbs),
                unit: "lbs"
            )
        }
    }

}

#Preview {
    WeightTrackingCard(summary: MockTrackerRepository.dashboard().weight) {}
        .padding()
        .background(TPCColor.background)
}
