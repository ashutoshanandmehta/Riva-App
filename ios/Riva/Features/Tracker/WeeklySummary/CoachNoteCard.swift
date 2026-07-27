import SwiftUI

/// Tinted coaching note with brand-highlighted emphasis.
struct CoachNoteCard: View {
    let note: CoachNote

    var body: some View {
        RivaCard(style: .tinted) {
            HStack(alignment: .top, spacing: TPCSpacing.sm) {
                avatar

                Text(AttributedString.rivaHighlighted(markdown: note.message))
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TPCColor.textOnBrand)
            .frame(width: 38, height: 38)
            .background(TPCColor.brand, in: Circle())
    }
}

#Preview {
    CoachNoteCard(note: MockTrackerRepository.summary().coachNote)
        .padding()
        .background(TPCColor.background)
}
