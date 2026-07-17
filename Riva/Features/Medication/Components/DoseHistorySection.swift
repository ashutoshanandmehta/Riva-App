import SwiftUI

/// "Dose History" — a vertical timeline of past injections, most recent
/// first, each with the site used.
struct DoseHistorySection: View {
    let records: [DoseRecord]
    let onSelect: (DoseRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            Text("Dose History")
                .font(RivaFont.sectionTitle)
                .foregroundStyle(RivaColor.textPrimary)

            VStack(spacing: RivaSpacing.sm) {
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
                    .foregroundStyle(RivaColor.textPrimary)
                Text(RivaFormat.mediumDate(record.date))
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RivaColor.textTertiary)
                Text(record.site)
                    .font(.system(size: 12))
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
        .padding(RivaSpacing.sm)
        .background(
            RivaColor.surface,
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
        )
        .rivaSurfaceOutline(cornerRadius: RivaRadius.tile)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: Timeline

    /// Dot + connector line column at the row's leading edge. The latest
    /// entry gets a filled brand dot; the line stops at the last entry.
    private func timelineMarker(isLatest: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RivaColor.brandSoft)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(isLatest ? 0 : 1)

            Circle()
                .fill(isLatest ? RivaColor.brand : RivaColor.brandSoft)
                .frame(width: 10, height: 10)

            Rectangle()
                .fill(RivaColor.brandSoft)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 10)
        .padding(.vertical, isLatest || isLast ? 0 : -RivaSpacing.sm)
    }
}

#Preview {
    DoseHistorySection(records: MockMedicationRepository.dashboard().history) { _ in }
        .padding()
        .background(RivaColor.background)
}
