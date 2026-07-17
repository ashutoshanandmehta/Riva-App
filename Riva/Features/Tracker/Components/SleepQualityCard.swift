import SwiftUI

/// Sleep quality tile — last night's duration, efficiency, and a mini
/// bar strip of recent nights, with a quick-log button.
struct SleepQualityCard: View {
    let sleep: SleepStatus
    /// Quick-log last night's sleep (placeholder for now).
    let onAdd: () -> Void

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Text("Sleep quality")
                    .rivaOverline()

                Text(RivaFormat.sleepDuration(minutes: sleep.durationMinutes))
                    .font(RivaFont.metricM)
                    .foregroundStyle(RivaColor.textPrimary)

                HStack(spacing: 5) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(RivaColor.brand)
                    Text("\(RivaFormat.percent(sleep.efficiency)) efficiency")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RivaColor.brand)
                }

                Spacer()

                bars
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Sleep: \(RivaFormat.sleepDuration(minutes: sleep.durationMinutes)), \(RivaFormat.percent(sleep.efficiency)) efficiency"
        )
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: RivaSpacing.xs) {
            ForEach(Array(sleep.recentNights.enumerated()), id: \.offset) { _, night in
                Capsule()
                    .fill(RivaColor.textPrimary.opacity(0.8))
                    .frame(width: 4)
                    .frame(height: max(44 * night, 6))
            }
            Spacer(minLength: RivaSpacing.xs)
            RivaQuickAddButton(accessibilityLabel: "Log sleep", action: onAdd)
        }
        .frame(height: 44, alignment: .bottom)
    }
}

#Preview {
    SleepQualityCard(sleep: MockTrackerRepository.dashboard().sleep) {}
        .frame(width: 170, height: 200)
        .padding()
        .background(RivaColor.background)
}
