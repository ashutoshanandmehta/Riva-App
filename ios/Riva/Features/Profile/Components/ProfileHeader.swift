import SwiftUI

/// Avatar (initials fallback with an edit badge) and the account name.
struct ProfileHeader: View {
    /// Profile name from the backend; may be empty on a fresh account.
    let name: String
    let onEdit: () -> Void

    private var displayName: String {
        name.isEmpty ? "there" : name
    }

    private var initials: String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
        return letters.isEmpty ? "R" : letters
    }

    var body: some View {
        VStack(spacing: TPCSpacing.sm) {
            avatar
            VStack(spacing: TPCSpacing.xxs) {
                Text(displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TPCColor.textPrimary)
                Text("TPC member")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TPCSpacing.xs)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [TPCColor.brandSoft, TPCColor.brandWash],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(TPCColor.brandDeep)
        }
        .frame(width: 78, height: 78)
        .overlay(alignment: .bottomTrailing) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TPCColor.textOnBrand)
                    .frame(width: 26, height: 26)
                    .background(TPCColor.brandDeep, in: Circle())
                    .overlay(Circle().stroke(TPCColor.background, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile")
        }
    }
}

#Preview {
    ProfileHeader(name: MockAccountRepository.sampleBundle.profile.name) {}
        .padding()
        .background(TPCColor.background)
}
