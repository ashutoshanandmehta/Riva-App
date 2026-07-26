import SwiftUI

/// Consistent "coming soon" sheet shown by every not-yet-built control, so
/// placeholder taps always respond visibly.
struct PlaceholderSheet: View {
    let context: PlaceholderContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: TPCSpacing.lg) {
            Image(systemName: context.systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(TPCColor.brand)
                .frame(width: 76, height: 76)
                .background(TPCColor.brandWash, in: Circle())
                .padding(.top, TPCSpacing.xl)

            VStack(spacing: TPCSpacing.xs) {
                Text(context.title)
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text(context.message)
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TPCSpacing.xl)

            Spacer()

            Button("Got it") { dismiss() }
                .buttonStyle(.rivaPrimary)
                .padding(.horizontal, TPCSpacing.lg)
                .padding(.bottom, TPCSpacing.lg)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(TPCColor.background)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PlaceholderSheet(context: .logShot)
    }
}
