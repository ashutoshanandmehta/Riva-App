import Foundation

/// Account sign-in and session management.
///
/// UI code depends only on this protocol; the live implementation talks to
/// Supabase Auth (Google OAuth today, with an email code path kept for
/// later; no passwords in the app).
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
