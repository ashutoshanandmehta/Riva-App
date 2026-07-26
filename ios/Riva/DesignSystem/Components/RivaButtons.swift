import SwiftUI

/// Primary filled call-to-action button — gold fill, cream text.
struct TPCPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPCFont.bodyBold)
            .foregroundStyle(TPCColor.textOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                configuration.isPressed ? TPCColor.brandHover : TPCColor.brand,
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TPCPrimaryButtonStyle {
    static var tpcPrimary: TPCPrimaryButtonStyle { TPCPrimaryButtonStyle() }
    /// Legacy alias.
    static var rivaPrimary: TPCPrimaryButtonStyle { TPCPrimaryButtonStyle() }
}

/// Secondary outlined button — forest green border, dark text, transparent fill.
struct TPCSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPCFont.bodyBold)
            .foregroundStyle(TPCColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: TPCRadius.control, style: .continuous)
                    .strokeBorder(TPCColor.surfaceOutline.opacity(1.8), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TPCSecondaryButtonStyle {
    static var tpcSecondary: TPCSecondaryButtonStyle { TPCSecondaryButtonStyle() }
}

/// Dark inverse button — forest green fill, cream text (e.g. "+ Log food").
struct TPCInverseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPCFont.captionEmphasized)
            .foregroundStyle(TPCColor.textOnInversePrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                configuration.isPressed ? TPCColor.brandMid : TPCColor.brandDeep,
                in: Capsule()
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TPCInverseButtonStyle {
    static var tpcInverse: TPCInverseButtonStyle { TPCInverseButtonStyle() }
}

/// Soft destructive button — danger text on a faint danger-tinted fill.
struct TPCDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPCFont.bodyBold)
            .foregroundStyle(TPCColor.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                TPCColor.danger.opacity(0.10),
                in: RoundedRectangle(cornerRadius: TPCRadius.control, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TPCDestructiveButtonStyle {
    static var tpcDestructive: TPCDestructiveButtonStyle { TPCDestructiveButtonStyle() }
    /// Legacy alias.
    static var rivaDestructive: TPCDestructiveButtonStyle { TPCDestructiveButtonStyle() }
}

#Preview {
    VStack(spacing: 12) {
        Button("Check if you qualify") {}
            .buttonStyle(.tpcPrimary)
        Button("Sign in") {}
            .buttonStyle(.tpcSecondary)
        Button("+ Log food") {}
            .buttonStyle(.tpcInverse)
        Button("Log Out") {}
            .buttonStyle(.tpcDestructive)
    }
    .padding()
    .background(TPCColor.background)
}
