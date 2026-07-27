import Foundation

/// Account sign-in and session management.
///
/// UI code depends only on this protocol; the live implementation talks to
/// Supabase Auth — Google OAuth, Sign in with Apple, and email + password.
///
/// Passwords are never stored by the app or by our backend: GoTrue keeps a
/// bcrypt hash in `auth.users` and that is the only copy that exists.
protocol AuthRepository: Sendable {
    /// The persisted session, if any. May be expired; use
    /// `validAccessToken()` before calling an authenticated API.
    func currentSession() async -> AuthSession?

    /// Emails a six digit sign-in code. Creates the account on first use.
    func requestCode(email: String) async throws

    /// Exchanges the emailed code for a session.
    @discardableResult
    func verifyCode(email: String, code: String) async throws -> AuthSession

    /// Adopts the token fragment from an OAuth redirect (Google sign in via
    /// the system web session) as this device's session.
    @discardableResult
    func adoptOAuthCallback(_ callback: URL) async throws -> AuthSession

    /// Exchanges an Apple identity token for a session. Native Sign in with
    /// Apple hands back a signed JWT rather than an OAuth redirect, so this
    /// goes to GoTrue's id_token grant instead of `adoptOAuthCallback`.
    ///
    /// `nonce` is the raw value; the token embeds its SHA256 hash, and Apple
    /// verifies the pair to bind the token to this sign-in attempt.
    @discardableResult
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession

    /// Signs in to an existing email + password account.
    @discardableResult
    func signIn(email: String, password: String) async throws -> AuthSession

    /// Sets the password on the account behind the *current* session.
    ///
    /// Both email flows end here: sign-up confirms the address with a code
    /// first (which yields a session), then chooses a password; reset does the
    /// same with a recovery code. Requires a live session.
    func updatePassword(_ password: String) async throws

    /// Emails a six digit password reset code to an existing account.
    func requestPasswordReset(email: String) async throws

    /// Exchanges a reset code for the session that `updatePassword` needs.
    @discardableResult
    func verifyPasswordReset(email: String, code: String) async throws -> AuthSession

    /// A usable access token, refreshing behind the scenes when the current
    /// one is about to expire. Returns nil when signed out (or the refresh
    /// was rejected), which means the UI should show sign-in.
    func validAccessToken() async throws -> String?

    func signOut() async

    /// Starts this device over with a fresh account: clears the stored
    /// session and any persisted device identity, so the next authenticated
    /// call provisions a brand new account.
    func resetIdentity() async
}

enum AuthError: LocalizedError {
    case service(String)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .service(let message): message
        case .unreachable: "Could not reach the sign in service. Check your connection and try again."
        }
    }
}
