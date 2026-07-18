import SwiftUI

/// Brand row shown at the top of every main tab: Riva logo + wordmark on the
/// left, settings on the right. Pushed sub-screens pass `onBack` to prepend
/// a back chevron; screens without a settings affordance (e.g. the profile
/// itself) pass `onSettings: nil`.
struct BrandTopBar: View {
    var onBack: (() -> Void)?
    var onSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: RivaSpacing.xs) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(RivaColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(RivaColor.surface, in: Circle())
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .padding(.trailing, RivaSpacing.xxs)
            }

            logo
            Text("Riva")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(RivaColor.textPrimary)

            Spacer()

            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(RivaColor.textSecondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
    }

    private var logo: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [RivaColor.brand, RivaColor.brandDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "water.waves")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
    }
}

#Preview {
    BrandTopBar {}
        .padding()
        .background(RivaColor.background)
}
