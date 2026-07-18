import AuthenticationServices
import UIKit

/// Async wrapper around ASWebAuthenticationSession for the Google flow.
/// The system sheet handles the whole OAuth dance and hands back the
/// custom-scheme callback URL with the session tokens in its fragment.
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {

    private var activeSession: ASWebAuthenticationSession?

    func signIn(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let sessionError = error as? ASWebAuthenticationSessionError,
                          sessionError.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.service("Sign in was canceled."))
                } else {
                    continuation.resume(throwing: AuthError.unreachable)
                }
            }
            session.presentationContextProvider = self
            activeSession = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
