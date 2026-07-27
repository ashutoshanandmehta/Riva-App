import SwiftUI

/// Standard in-scroll loading state used by dashboard screens.
struct LoadingStateView: View {
    var message = "Loading…"

    var body: some View {
        VStack(spacing: TPCSpacing.md) {
            ProgressView()
            Text(message)
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textSecondary)
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
        VStack(spacing: TPCSpacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(TPCColor.textSecondary)
            Text(message)
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.brand)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
        .padding(.horizontal, TPCSpacing.xxl)
    }
}

#Preview("Loading") {
    LoadingStateView(message: "Loading your day…")
}

#Preview("Error") {
    ErrorStateView(message: "Couldn't load your dashboard. Pull to retry.") {}
}
