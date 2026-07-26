import SwiftUI

/// Brand row shown at the top of every main tab: TPC gold seal + wordmark on
/// the left, settings on the right. Pushed sub-screens pass `onBack` to
/// prepend a back chevron; screens without a settings affordance pass
/// `onSettings: nil`.
struct BrandTopBar: View {
    var onBack: (() -> Void)?
    var onSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: TPCSpacing.xs) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TPCColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(TPCColor.surface, in: Circle())
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .padding(.trailing, TPCSpacing.xxs)
            }

            tpcSeal
            Text("The Peptide Company")
                .tpcOverline(TPCColor.accentLink)

            Spacer()

            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(TPCColor.textSecondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
    }

    private var tpcSeal: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xB08A2E), Color(hex: 0x7E5F14)],
                        center: UnitPoint(x: 0.4, y: 0.3),
                        startRadius: 0,
                        endRadius: 15
                    )
                )
                .overlay(
                    Circle()
                        .strokeBorder(TPCColor.accentPale.opacity(0.45), lineWidth: 1)
                )
            Text("TPC")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: 0xFBF7EC))
        }
        .frame(width: 30, height: 30)
    }
}

#Preview {
    BrandTopBar(onSettings: {})
        .padding()
        .background(TPCColor.background)
}
