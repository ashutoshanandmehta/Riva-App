import AuthenticationServices
import UIKit

/// Async wrapper around ASAuthorizationController for Sign in with Apple.
///
/// `AppleSignInButton` is a custom control, so it has no
/// `SignInWithAppleButton` request/completion closures to hang the flow off.
/// This drives the controller directly and hands back exactly the `Result`
/// `AuthModel.completeAppleSignIn(_:fromLogin:)` already expects.
@MainActor
final class AppleAuthSession: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorization, any Error>?
    private var activeController: ASAuthorizationController?

    /// `hashedNonce` is the SHA256 returned by `AuthModel.prepareAppleNonce()`.
    /// Cancellation surfaces as an `ASAuthorizationError`, which the model
    /// already swallows rather than reporting.
    func authorize(hashedNonce: String) async -> Result<ASAuthorization, any Error> {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        activeController = controller

        do {
            let authorization = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                controller.performRequests()
            }
            return .success(authorization)
        } catch {
            return .failure(error)
        }
    }

    private func finish(_ result: Result<ASAuthorization, any Error>) {
        activeController = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    // MARK: ASAuthorizationControllerDelegate

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
