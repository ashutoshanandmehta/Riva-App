import SwiftUI

/// Avatar (initials fallback with an edit badge), name, and email.
struct ProfileHeader: View {
    let profile: ProfileSnapshot
    /// Edit avatar/profile (placeholder for now).
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: RivaSpacing.sm) {
            avatar
            VStack(spacing: RivaSpacing.xxs) {
                Text(profile.fullName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(RivaColor.textPrimary)
                Text(profile.email)
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, RivaSpacing.xs)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [RivaColor.brandSoft, RivaColor.brandWash],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(profile.initials)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(RivaColor.brandDeep)
        }
        .frame(width: 78, height: 78)
        .overlay(alignment: .bottomTrailing) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RivaColor.textOnBrand)
                    .frame(width: 26, height: 26)
                    .background(RivaColor.brandDeep, in: Circle())
                    .overlay(Circle().stroke(RivaColor.background, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile photo")
        }
    }
}

#Preview {
    ProfileHeader(profile: MockProfileRepository.snapshot()) {}
        .padding()
        .background(RivaColor.background)
}
