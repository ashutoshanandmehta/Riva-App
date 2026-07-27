import SwiftUI

/// The email + password entry point, sitting under the Google and Apple
/// buttons on both the onboarding and login screens.
///
/// Outlined rather than filled so it reads as the third option instead of
/// competing with the provider buttons above it. Mirrors
/// `AppleSignInButton`'s `fromLogin` split: sign-up runs the code wizard,
/// login goes straight to the credentials form.
struct EmailAuthButton: View {
    @Bindable var model: AuthModel
    let fromLogin: Bool

    var body: some View {
        Button {
            if fromLogin {
                model.showEmailLogin()
            } else {
                model.startEmailSignUp()
            }
        } label: {
            HStack(spacing: TPCSpacing.xs) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(fromLogin ? "Sign in with email" : "Sign up with email")
            }
        }
        .buttonStyle(.tpcSecondary)
        .disabled(model.isWorking)
    }
}

#Preview {
    VStack(spacing: TPCSpacing.sm) {
        EmailAuthButton(
            model: AuthModel(repository: MockAuthRepository(), account: MockAccountRepository()),
            fromLogin: false
        )
        EmailAuthButton(
            model: AuthModel(repository: MockAuthRepository(), account: MockAccountRepository()),
            fromLogin: true
        )
    }
    .padding()
    .background(TPCColor.background)
}
