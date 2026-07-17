import SwiftUI

/// Full-screen placeholder for tabs whose features haven't shipped yet.
struct PlaceholderScreen: View {
    let title: String
    let icon: RivaIcon
    var iconScale: CGFloat = 1
    let blurb: String

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            RivaIconView(icon: icon, pointSize: 34, weight: .semibold, scale: iconScale)
                .foregroundStyle(RivaColor.brand)
                .frame(width: 88, height: 88)
                .background(RivaColor.brandWash, in: Circle())

            VStack(spacing: RivaSpacing.xs) {
                Text(title)
                    .font(RivaFont.sectionTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text(blurb)
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, RivaSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Optically center above the floating tab bar.
        .padding(.bottom, RivaLayout.tabBarClearance * 0.6)
        .background(RivaColor.background)
    }
}

#Preview {
    PlaceholderScreen(
        title: "Exercise",
        icon: .symbol("dumbbell"),
        blurb: "Workouts and movement tracking are coming soon."
    )
}
