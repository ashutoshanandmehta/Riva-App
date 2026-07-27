import SwiftUI

/// A brief, celebratory "Welcome back" splash shown over the app right after
/// a returning user logs in. Fades in, holds, then auto-dismisses into the
/// dashboard via `onDone`.
struct WelcomeBackView: View {
    /// The user's first name. Empty greets without a name.
    let name: String
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TPCColor.heroTop, TPCColor.heroMid, TPCColor.heroBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: TPCSpacing.lg) {
                TPCSeal(size: 96)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: TPCSpacing.xs) {
                    Text("Welcome back")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))

                    if !name.isEmpty {
                        Text(name)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Text("Your data is right where you left it.")
                        .font(TPCFont.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, TPCSpacing.xs)
                }
                .padding(.horizontal, TPCSpacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
        }
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appeared = true
            }
            try? await Task.sleep(for: .seconds(2.2))
            onDone()
        }
    }
}

#Preview {
    WelcomeBackView(name: "Dev") {}
}
