import SwiftUI

/// Consistent "coming soon" sheet shown by every not-yet-built control, so
/// placeholder taps always respond visibly.
struct PlaceholderSheet: View {
    let context: PlaceholderContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            Image(systemName: context.systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(RivaColor.brand)
                .frame(width: 76, height: 76)
                .background(RivaColor.brandWash, in: Circle())
                .padding(.top, RivaSpacing.xl)

            VStack(spacing: RivaSpacing.xs) {
                Text(context.title)
                    .font(RivaFont.sectionTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text(context.message)
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, RivaSpacing.xl)

            Spacer()

            Button("Got it") { dismiss() }
                .buttonStyle(.rivaPrimary)
                .padding(.horizontal, RivaSpacing.lg)
                .padding(.bottom, RivaSpacing.lg)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PlaceholderSheet(context: .logShot)
    }
}
