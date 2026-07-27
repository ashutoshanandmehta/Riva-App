import AuthenticationServices
import SwiftUI

/// Sign in with Apple, wired to `AuthModel`.
///
/// A custom button rather than `SignInWithAppleButton`: the system control
/// draws its own SF Pro label sized to the frame, which read as a different
/// typeface next to the Google and email buttons stacked with it. Apple
/// permits a custom button provided it keeps the Apple logo, one of the
/// approved titles, sufficient contrast, and equal prominence — all held
/// here; only the typeface is ours. `fromLogin` picks where a successful
/// sign-in lands, matching `continueWithGoogle(fromLogin:)`.
struct AppleSignInButton: View {
    @Bindable var model: AuthModel
    let fromLogin: Bool

    /// `.signUp` on the onboarding screen so it reads as an alternative to
    /// "Create account with Google" rather than a returning-user action.
    var label: Title = .signIn

    /// The only titles Apple allows on a Sign in with Apple button.
    enum Title: String {
        case signIn = "Sign in with Apple"
        case signUp = "Sign up with Apple"
    }

    @State private var session = AppleAuthSession()

    var body: some View {
        Button {
            Task {
                let result = await session.authorize(hashedNonce: model.prepareAppleNonce())
                await model.completeAppleSignIn(result, fromLogin: fromLogin)
            }
        } label: {
            HStack(spacing: TPCSpacing.xs) {
                // Same icon size as `EmailAuthButton`, so the stacked buttons
                // land on one height.
                Image(systemName: "apple.logo")
                    .font(.system(size: 15, weight: .semibold))
                Text(label.rawValue)
            }
        }
        .buttonStyle(AppleButtonStyle())
        .disabled(model.isWorking)
    }
}

/// Apple's button appearance, carrying the TPC label font. Black on light and
/// white on dark, which is Apple's own guidance and the only way the button
/// keeps an edge against the near-black dark background. The palette is
/// Apple's, so these are deliberately literal rather than brand tokens.
private struct AppleButtonStyle: ButtonStyle {
    private let fill = Color(light: 0x000000, dark: 0xFFFFFF)
    private let label = Color(light: 0xFFFFFF, dark: 0x000000)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPCFont.bodyBold)
            .foregroundStyle(label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(fill, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: TPCSpacing.sm) {
        Button("Create account with Google") {}
            .buttonStyle(.tpcPrimary)
        AppleSignInButton(
            model: AuthModel(
                repository: MockAuthRepository(),
                account: MockAccountRepository()
            ),
            fromLogin: false,
            label: .signUp
        )
        EmailAuthButton(
            model: AuthModel(repository: MockAuthRepository(), account: MockAccountRepository()),
            fromLogin: false
        )
    }
    .padding()
    .background(TPCColor.background)
}
