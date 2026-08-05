import SwiftUI

/// Static preview of who is on the user's care team. No repository, no
/// network — care team messaging has no backend yet, so this introduces the
/// clinician and wellness coach rather than pretending to chat with them.
struct CareTeamView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(CareTeamCopy.members) { member in
                    memberBlock(member)
                }

                Text(CareTeamCopy.footnote)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, TPCLayout.tabBarClearance)
        }
    }

    private func memberBlock(_ member: CareTeamMember) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                avatar(member.systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(TPCColor.textPrimary)

                    Text(member.role)
                        .font(TPCFont.overline)
                        .foregroundStyle(TPCColor.textFaint)
                        .textCase(.uppercase)
                }
            }

            CompanionBubble(text: member.intro, isUser: false)
                .frame(maxWidth: 302, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func avatar(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TPCColor.textOnBrand)
            .frame(width: 34, height: 34)
            .background(TPCColor.brand, in: Circle())
    }
}

#Preview {
    CareTeamView()
        .background(TPCColor.background)
}
