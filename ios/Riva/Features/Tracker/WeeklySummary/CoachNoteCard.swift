import SwiftUI

/// Tinted coaching note with brand-highlighted emphasis.
struct CoachNoteCard: View {
    let note: CoachNote

    var body: some View {
        RivaCard(style: .tinted) {
            HStack(alignment: .top, spacing: RivaSpacing.sm) {
                avatar

                Text(AttributedString.rivaHighlighted(markdown: note.message))
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(RivaColor.textOnBrand)
            .frame(width: 38, height: 38)
            .background(RivaColor.brand, in: Circle())
    }
}

#Preview {
    CoachNoteCard(note: MockTrackerRepository.summary().coachNote)
        .padding()
        .background(RivaColor.background)
}
