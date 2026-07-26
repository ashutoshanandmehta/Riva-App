import SwiftUI

/// "Medication" section of the summary: last/next dose tiles plus a Manage
/// shortcut into the Medication tab.
struct MedicationWeekSection: View {
    let lastDose: Date
    let nextDose: Date
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            HStack {
                Text("Medication")
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Spacer()
                Button(action: onManage) {
                    Text("Manage")
                        .rivaOverline(TPCColor.brand)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage medication")
            }

            HStack(spacing: TPCSpacing.md) {
                doseTile(systemImage: "checkmark.circle", caption: "Last dose", date: lastDose)
                doseTile(systemImage: "calendar", caption: "Next dose", date: nextDose)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func doseTile(systemImage: String, caption: String, date: Date) -> some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(TPCColor.brand)
                Text(caption)
                    .rivaOverline()
                Text(RivaFormat.monthDay(date))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TPCColor.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption): \(RivaFormat.monthDay(date))")
    }
}

#Preview {
    let summary = MockTrackerRepository.summary()
    return MedicationWeekSection(
        lastDose: summary.lastDoseDate,
        nextDose: summary.nextDoseDate
    ) {}
        .padding()
        .background(TPCColor.background)
}
