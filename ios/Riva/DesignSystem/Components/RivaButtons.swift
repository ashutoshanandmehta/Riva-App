import SwiftUI

/// Primary filled call-to-action button style ("Log today's shot").
struct RivaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(RivaColor.textOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RivaColor.brandDeep,
                in: RoundedRectangle(cornerRadius: RivaRadius.control, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RivaPrimaryButtonStyle {
    /// `Button("…") { }.buttonStyle(.rivaPrimary)`
    static var rivaPrimary: RivaPrimaryButtonStyle { RivaPrimaryButtonStyle() }
}

/// Soft destructive button style ("Log Out") — danger text on a faint
/// danger-tinted fill.
struct RivaDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(RivaColor.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RivaColor.danger.opacity(0.1),
                in: RoundedRectangle(cornerRadius: RivaRadius.control, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RivaDestructiveButtonStyle {
    /// `Button("Log Out") { }.buttonStyle(.rivaDestructive)`
    static var rivaDestructive: RivaDestructiveButtonStyle { RivaDestructiveButtonStyle() }
}

#Preview {
    Button("Log today's shot") {}
        .buttonStyle(.rivaPrimary)
        .padding()
        .background(RivaColor.background)
}
