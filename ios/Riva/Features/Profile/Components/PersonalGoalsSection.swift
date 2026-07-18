import SwiftUI

/// "Personal Goals" section: start and goal weight tiles with an Edit shortcut.
struct PersonalGoalsSection: View {
    let startWeightLbs: Double?
    let goalWeightLbs: Double?
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
                    caption: "Start Weight",
                    valueLbs: startWeightLbs
                )
                goalTile(
                    systemImage: "flag",
                    caption: "Goal Weight",
                    valueLbs: goalWeightLbs
                )
            }
        }
    }

    private func goalTile(systemImage: String, caption: String, valueLbs: Double?) -> some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(RivaColor.brand)
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(RivaColor.textSecondary)
                if let valueLbs {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(RivaFormat.weight(valueLbs))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(RivaColor.textPrimary)
                        Text("lbs")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RivaColor.textSecondary)
                    }
                } else {
                    Text("Not set")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(RivaColor.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            valueLbs.map { "\(caption): \(RivaFormat.weight($0)) pounds" } ?? "\(caption): not set"
        )
    }
}

#Preview {
    let profile = MockAccountRepository.sampleBundle.profile
    return PersonalGoalsSection(
        startWeightLbs: profile.startWeight,
        goalWeightLbs: profile.goalWeight
    ) {}
        .padding()
        .background(RivaColor.background)
}
