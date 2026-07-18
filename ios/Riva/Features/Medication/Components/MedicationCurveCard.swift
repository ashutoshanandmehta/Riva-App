import Charts
import SwiftUI

/// Modelled GLP-1 concentration across the current week, with a "you are
/// here" marker, a dotted therapeutic-threshold line, and a coaching note.
struct MedicationCurveCard: View {
    let curve: MedicationCurve
    let insight: RivaInsight
    /// Info button in the header (placeholder for the methodology sheet).
    let onInfo: () -> Void

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                header
                chart
                insightBanner
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Medication Curve")
                .font(RivaFont.cardTitle)
                .foregroundStyle(RivaColor.textPrimary)
            Spacer()
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(RivaColor.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About the medication curve")
        }
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            ForEach(curve.points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Base", 0),
                    yEnd: .value("Level", point.level)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [RivaColor.brand.opacity(0.16), RivaColor.brand.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Level", point.level)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .foregroundStyle(RivaColor.brand)
            }

            RuleMark(y: .value("Threshold", curve.therapeuticThreshold))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .foregroundStyle(RivaColor.textTertiary.opacity(0.55))

            if let today = curve.point(closestTo: .now) {
                // White halo behind the marker so it reads over the line.
                PointMark(x: .value("Time", today.date), y: .value("Level", today.level))
                    .symbolSize(150)
                    .foregroundStyle(RivaColor.surface)
                PointMark(x: .value("Time", today.date), y: .value("Level", today.level))
                    .symbolSize(70)
                    .foregroundStyle(RivaColor.brand)
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis(.hidden)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisValueLabel(anchor: value.as(Date.self) == axisDates.last ? .topTrailing : nil) {
                    if let date = value.as(Date.self) {
                        axisLabel(for: date)
                    }
                }
            }
        }
        .frame(height: 110)
        .accessibilityLabel("Estimated medication concentration across this week")
    }

    private func axisLabel(for date: Date) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: .now)
        return Text(isToday ? "TODAY" : RivaFormat.weekdayName(date).prefix(3).uppercased())
            .font(.system(size: 10, weight: isToday ? .bold : .semibold))
            .kerning(0.5)
            .foregroundStyle(isToday ? RivaColor.brand : RivaColor.textTertiary)
    }

    private var yMax: Double {
        (curve.points.map(\.level).max() ?? 1) * 1.2
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = curve.points.first?.date, let last = curve.points.last?.date else {
            return Date()...Date().addingTimeInterval(1)
        }
        return first...last
    }

    /// Mon / Wed / Sun anchors plus "today", deduplicating any anchor that
    /// falls on the same day as today.
    private var axisDates: [Date] {
        guard let weekStart = curve.points.first?.date else { return [] }
        let calendar = Calendar.current
        let now = Date()
        let anchors = [0, 2, 6].compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
        var dates = anchors.filter { !calendar.isDate($0, inSameDayAs: now) }
        if let today = curve.point(closestTo: now)?.date {
            dates.append(today)
        }
        return dates.sorted()
    }

    // MARK: Insight

    private var insightBanner: some View {
        HStack(alignment: .top, spacing: RivaSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RivaColor.brand)
                .padding(.top, 1)
            Text(insight.message)
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RivaSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RivaColor.brandWash,
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
        )
    }
}

#Preview {
    let dashboard = MockMedicationRepository.dashboard()
    return MedicationCurveCard(curve: dashboard.curve, insight: dashboard.insight) {}
        .padding()
        .background(RivaColor.background)
}
