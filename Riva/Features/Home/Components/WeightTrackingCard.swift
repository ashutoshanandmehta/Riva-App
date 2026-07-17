import Charts
import SwiftUI

/// Weight Tracking card: monthly trend chart, weekly/total deltas, and goal
/// progress toward the target weight.
struct WeightTrackingCard: View {
    let summary: WeightSummary

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                header
                chart
                statTiles
                goalProgress
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: RivaSpacing.xs) {
            RivaIconChip(systemImage: "chart.xyaxis.line")
            Text("Weight Tracking")
                .font(RivaFont.cardTitle)
                .foregroundStyle(RivaColor.textPrimary)
            Spacer()
            RivaBadge(text: "Past month")
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
            .foregroundStyle(RivaColor.brand)
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
                            .foregroundStyle(RivaColor.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                    .foregroundStyle(RivaColor.brandSoft.opacity(0.8))
                AxisValueLabel()
                    .font(.system(size: 10))
                    .foregroundStyle(RivaColor.textTertiary)
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
        HStack(spacing: RivaSpacing.sm) {
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

    // MARK: Goal progress

    private var goalProgress: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                    Text("Goal progress")
                        .rivaOverline()
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(RivaFormat.weight(summary.currentLbs))
                            .font(RivaFont.metricXL)
                            .foregroundStyle(RivaColor.textPrimary)
                        Text("lbs")
                            .font(RivaFont.metricUnit)
                            .foregroundStyle(RivaColor.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: RivaSpacing.xxs) {
                    Text("Target")
                        .rivaOverline()
                    Text("\(RivaFormat.weight(summary.targetLbs).replacingOccurrences(of: ".0", with: "")) lbs")
                        .font(RivaFont.captionEmphasized)
                        .foregroundStyle(RivaColor.brand)
                }
            }

            RivaProgressBar(progress: summary.goalProgress)

            HStack {
                Text("\(Int((summary.goalProgress * 100).rounded()))% complete")
                Spacer()
                Text("\(RivaFormat.weight(summary.lbsToGo)) lbs to go")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(RivaColor.textSecondary)
        }
    }
}

#Preview {
    WeightTrackingCard(summary: MockHomeRepository.snapshot().weight)
        .padding()
        .background(RivaColor.background)
}
