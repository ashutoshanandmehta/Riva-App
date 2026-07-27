import AuthenticationServices
import SwiftUI

/// Apple's own Sign in with Apple control, wired to `AuthModel`.
///
/// The button appearance is Apple's and must stay that way — App Review
/// rejects restyled versions — so this only owns the sizing and the nonce
/// handshake. `fromLogin` picks where a successful sign-in lands, matching
/// `continueWithGoogle(fromLogin:)`.
struct AppleSignInButton: View {
    @Bindable var model: AuthModel
    let fromLogin: Bool

    /// `.signUp` on the onboarding screen so it reads as an alternative to
    /// "Create account with Google" rather than a returning-user action.
    var label: SignInWithAppleButton.Label = .signIn

    var body: some View {
        SignInWithAppleButton(label) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = model.prepareAppleNonce()
        } onCompletion: { result in
            Task { await model.completeAppleSignIn(result, fromLogin: fromLogin) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(Capsule())
        .disabled(model.isWorking)
    }
}

#Preview {
    AppleSignInButton(
        model: AuthModel(
            repository: MockAuthRepository(),
            account: MockAccountRepository()
        ),
        fromLogin: true
    )
    .padding()
    .background(TPCColor.background)
}
