import SwiftUI

/// Full-screen placeholder for tabs whose features haven't shipped yet.
struct PlaceholderScreen: View {
    let title: String
    let icon: RivaIcon
    var iconScale: CGFloat = 1
    let blurb: String

    var body: some View {
        VStack(spacing: TPCSpacing.lg) {
            RivaIconView(icon: icon, pointSize: 34, weight: .semibold, scale: iconScale)
                .foregroundStyle(TPCColor.brand)
                .frame(width: 88, height: 88)
                .background(TPCColor.brandWash, in: Circle())

            VStack(spacing: TPCSpacing.xs) {
                Text(title)
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text(blurb)
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TPCSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Optically center above the floating tab bar.
        .padding(.bottom, TPCLayout.tabBarClearance * 0.6)
        .background(TPCColor.background)
    }
}

#Preview {
    PlaceholderScreen(
        title: "Exercise",
        icon: .symbol("dumbbell"),
        blurb: "Workouts and movement tracking are coming soon."
    )
}
