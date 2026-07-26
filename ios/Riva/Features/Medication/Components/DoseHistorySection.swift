import SwiftUI

/// "Dose History" — a vertical timeline of past injections, most recent
/// first, each with the site used.
struct DoseHistorySection: View {
    let records: [DoseRecord]
    let onSelect: (DoseRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            Text("Dose History")
                .font(TPCFont.sectionTitle)
                .foregroundStyle(TPCColor.textPrimary)

            VStack(spacing: TPCSpacing.sm) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    row(record, isLatest: index == 0, isLast: index == records.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Row

    private func row(_ record: DoseRecord, isLatest: Bool, isLast: Bool) -> some View {
        Button {
            onSelect(record)
        } label: {
            rowCard(record)
                .padding(.leading, 26)
                .overlay(alignment: .leading) {
                    timelineMarker(isLatest: isLatest, isLast: isLast)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Week \(record.week), \(RivaFormat.doseMg(record.doseMg)) on \(RivaFormat.mediumDate(record.date)), \(record.site)"
        )
    }

    private func rowCard(_ record: DoseRecord) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Week \(record.week) • \(RivaFormat.doseMgCompact(record.doseMg))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TPCColor.textPrimary)
                Text(RivaFormat.mediumDate(record.date))
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TPCColor.textTertiary)
                Text(record.site)
                    .font(.system(size: 12))
                    .foregroundStyle(TPCColor.textSecondary)
            }
        }
        .padding(TPCSpacing.sm)
        .background(
            TPCColor.surface,
            in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
        )
        .rivaSurfaceOutline(cornerRadius: TPCRadius.tile)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: Timeline

    /// Dot + connector line column at the row's leading edge. The latest
    /// entry gets a filled brand dot; the line stops at the last entry.
    private func timelineMarker(isLatest: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(TPCColor.brandSoft)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(isLatest ? 0 : 1)

            Circle()
                .fill(isLatest ? TPCColor.brand : TPCColor.brandSoft)
                .frame(width: 10, height: 10)

            Rectangle()
                .fill(TPCColor.brandSoft)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 10)
        .padding(.vertical, isLatest || isLast ? 0 : -TPCSpacing.sm)
    }
}

#Preview {
    DoseHistorySection(records: MockMedicationRepository.dashboard().history) { _ in }
        .padding()
        .background(TPCColor.background)
}
