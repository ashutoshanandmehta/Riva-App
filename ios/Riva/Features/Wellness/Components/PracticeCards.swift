import SwiftUI

/// Card styles for the Wellness catalog: a full-width row, a grid tile,
/// and a horizontally scrolling suggestion card.

// MARK: - Duration chip

/// Small "(clock) 15 min" capsule shared by all three cards.
private struct DurationChip: View {
    let text: String

    var body: some View {
        HStack(spacing: TPCSpacing.xxs) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(TPCFont.captionEmphasized)
        }
        .foregroundStyle(TPCColor.brand)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(TPCColor.brandSoft, in: Capsule())
    }
}

// MARK: - Row card

/// Full-width practice row (dark-green circle icon, title, subtitle,
/// duration chip on the right).
struct PracticeRowCard: View {
    let practice: WellnessPractice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RivaCard {
                HStack(spacing: TPCSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(TPCColor.heroCard)
                            .frame(width: 48, height: 48)
                        Image(systemName: practice.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(TPCColor.textOnInversePrimary)
                    }
                    VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                        Text(practice.kind.title)
                            .font(TPCFont.cardTitle)
                            .foregroundStyle(TPCColor.textPrimary)
                        Text(practice.title)
                            .font(TPCFont.footnote)
                            .foregroundStyle(TPCColor.textSecondary)
                    }
                    Spacer()
                    DurationChip(text: practice.durationText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tile card

/// Two-column grid tile (square icon chip, bold title, subtitle, chip).
struct PracticeTileCard: View {
    let practice: WellnessPractice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RivaCard {
                VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                    RivaIconChip(
                        systemImage: practice.icon,
                        tint: TPCColor.brand,
                        background: TPCColor.brandSoft,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                        Text(practice.kind.title)
                            .font(TPCFont.cardTitle)
                            .foregroundStyle(TPCColor.textPrimary)
                        Text(practice.title)
                            .font(TPCFont.footnote)
                            .foregroundStyle(TPCColor.textSecondary)
                            .lineLimit(1)
                    }
                    DurationChip(text: practice.durationText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggested card

/// Horizontally scrolling suggestion (olive circular icon chip, title,
/// "7 min · Mind", reason footnote).
struct SuggestedPracticeCard: View {
    let suggestion: SuggestedPractice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RivaCard {
                VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(TPCColor.fillNeutral)
                            .frame(width: 40, height: 40)
                        Image(systemName: suggestion.practice.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(TPCColor.wellnessAccent)
                    }
                    VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                        Text(suggestion.practice.title)
                            .font(TPCFont.cardTitle)
                            .foregroundStyle(TPCColor.textPrimary)
                        Text("\(suggestion.practice.durationText) · \(suggestion.practice.kind.title)")
                            .font(TPCFont.footnote)
                            .foregroundStyle(TPCColor.textSecondary)
                    }
                    Text(suggestion.reason)
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textTertiary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .frame(width: 200)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: TPCSpacing.md) {
            PracticeRowCard(practice: WellnessPractice.catalog[0]) {}
            HStack(alignment: .top, spacing: TPCSpacing.md) {
                PracticeTileCard(practice: WellnessPractice.practice(id: "exercise_walk")!) {}
                PracticeTileCard(practice: WellnessPractice.practice(id: "meditation_isha")!) {}
            }
            SuggestedPracticeCard(
                suggestion: SuggestedPractice(
                    practice: WellnessPractice.practice(id: "mind_gratitude")!,
                    reason: "A grateful pause keeps your streak going."
                )
            ) {}
        }
        .padding()
    }
    .background(TPCColor.background)
}
