import SwiftUI

/// "Personal Goals" — current and goal weight tiles with an Edit shortcut.
struct PersonalGoalsSection: View {
    let goals: PersonalGoals
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            HStack {
                Text("Personal goals")
                    .rivaOverline()
                Spacer()
                Button(action: onEdit) {
                    Text("Edit")
                        .font(RivaFont.captionEmphasized)
                        .foregroundStyle(RivaColor.brand)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit goals")
            }

            HStack(spacing: RivaSpacing.md) {
                goalTile(
                    systemImage: "scalemass",
                    caption: "Current Weight",
                    valueLbs: goals.currentWeightLbs
                )
                goalTile(
                    systemImage: "flag",
                    caption: "Goal Weight",
                    valueLbs: goals.goalWeightLbs
                )
            }
        }
    }

    private func goalTile(systemImage: String, caption: String, valueLbs: Double) -> some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(RivaColor.brand)
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(RivaColor.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(RivaFormat.weight(valueLbs))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(RivaColor.textPrimary)
                    Text("lbs")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RivaColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption): \(RivaFormat.weight(valueLbs)) pounds")
    }
}

#Preview {
    PersonalGoalsSection(goals: MockProfileRepository.snapshot().goals) {}
        .padding()
        .background(RivaColor.background)
}
