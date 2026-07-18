import SwiftUI

/// Standard in-scroll loading state used by dashboard screens.
struct LoadingStateView: View {
    var message = "Loading…"

    var body: some View {
        VStack(spacing: RivaSpacing.md) {
            ProgressView()
            Text(message)
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 160)
    }
}

/// Standard in-scroll error state with a retry affordance.
struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: RivaSpacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(RivaColor.textSecondary)
            Text(message)
                .font(RivaFont.body)
                .foregroundStyle(RivaColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .font(RivaFont.captionEmphasized)
                .foregroundStyle(RivaColor.brand)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
        .padding(.horizontal, RivaSpacing.xxl)
    }
}

#Preview("Loading") {
    LoadingStateView(message: "Loading your day…")
}

#Preview("Error") {
    ErrorStateView(message: "Couldn't load your dashboard. Pull to retry.") {}
}
