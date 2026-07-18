import Foundation

/// A signed-in Supabase session, persisted in the Keychain.
struct AuthSession: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    /// Unix time when the access token expires.
    let expiresAt: Date
    let userID: String
    let email: String?

    /// True while the access token is safely usable (with a one minute
    /// margin so a request never rides an about-to-expire token).
    var isFresh: Bool {
        expiresAt.timeIntervalSinceNow > 60
    }
}
