import SwiftUI

/// Card styles for the Wellness catalog: a full-width row, a grid tile,
/// and a horizontally scrolling suggestion card.

// MARK: - Duration chip

/// Small "(clock) 15 min" capsule shared by all three cards.
private struct DurationChip: View {
    let text: String

    var body: some View {
        HStack(spacing: RivaSpacing.xxs) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(RivaFont.captionEmphasized)
        }
        .foregroundStyle(RivaColor.brand)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RivaColor.brandSoft, in: Capsule())
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
                HStack(spacing: RivaSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(RivaColor.heroCard)
                            .frame(width: 48, height: 48)
                        Image(systemName: practice.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(RivaColor.textOnInversePrimary)
                    }
                    VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                        Text(practice.kind.title)
                            .font(RivaFont.cardTitle)
                            .foregroundStyle(RivaColor.textPrimary)
                        Text(practice.title)
                            .font(RivaFont.footnote)
                            .foregroundStyle(RivaColor.textSecondary)
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
                VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                    RivaIconChip(
                        systemImage: practice.icon,
                        tint: RivaColor.brand,
                        background: RivaColor.brandSoft,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                        Text(practice.kind.title)
                            .font(RivaFont.cardTitle)
                            .foregroundStyle(RivaColor.textPrimary)
                        Text(practice.title)
                            .font(RivaFont.footnote)
                            .foregroundStyle(RivaColor.textSecondary)
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
                VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(RivaColor.fillNeutral)
                            .frame(width: 40, height: 40)
                        Image(systemName: suggestion.practice.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(RivaColor.wellnessAccent)
                    }
                    VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                        Text(suggestion.practice.title)
                            .font(RivaFont.cardTitle)
                            .foregroundStyle(RivaColor.textPrimary)
                        Text("\(suggestion.practice.durationText) · \(suggestion.practice.kind.title)")
                            .font(RivaFont.footnote)
                            .foregroundStyle(RivaColor.textSecondary)
                    }
                    Text(suggestion.reason)
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textTertiary)
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
        VStack(spacing: RivaSpacing.md) {
            PracticeRowCard(practice: WellnessPractice.catalog[0]) {}
            HStack(alignment: .top, spacing: RivaSpacing.md) {
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
    .background(RivaColor.background)
}
