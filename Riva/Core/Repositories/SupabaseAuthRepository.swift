import Foundation

/// Supabase Auth (GoTrue) over plain URLSession: email code sign-in, session
/// persistence in the Keychain, and silent refresh.
///
/// Deliberately dependency-free; if the app later adopts the Supabase SDK,
/// only this file changes.
actor SupabaseAuthRepository: AuthRepository {

    private static let sessionKey = "auth.session"

    private let baseURL: URL
    private let anonKey: String
    private let urlSession: URLSession
    private var session: AuthSession?

    init(baseURL: URL = BackendEnvironment.supabaseURL,
         anonKey: String = BackendEnvironment.supabaseAnonKey) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config)
        if let data = KeychainStore.load(key: Self.sessionKey) {
            session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
        #if DEBUG
        // Test hook: inject a session so automated runs skip the email code.
        // -riva.accessToken <jwt> -riva.refreshToken <token>
        if let accessToken = UserDefaults.standard.string(forKey: "riva.accessToken"),
           let refreshToken = UserDefaults.standard.string(forKey: "riva.refreshToken") {
            session = AuthSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: Date().addingTimeInterval(3000),
                userID: "debug-injected",
                email: "debug@riva.test"
            )
        }
        #endif
    }

    func currentSession() async -> AuthSession? { session }

    func requestCode(email: String) async throws {
        let body = ["email": email, "create_user": true] as [String: Any]
        _ = try await call(path: "auth/v1/otp", body: body)
    }

    @discardableResult
    func verifyCode(email: String, code: String) async throws -> AuthSession {
        let body = ["type": "email", "email": email, "token": code]
        let data = try await call(path: "auth/v1/verify", body: body)
        return try adopt(tokenData: data)
    }

    func validAccessToken() async throws -> String? {
        guard let current = session else { return nil }
        if current.isFresh { return current.accessToken }
        do {
            let data = try await call(
                path: "auth/v1/token?grant_type=refresh_token",
                body: ["refresh_token": current.refreshToken]
            )
            return try adopt(tokenData: data).accessToken
        } catch AuthError.service {
            // Refresh token rejected (revoked or already used): sign-in again.
            await signOut()
            return nil
        }
    }

    func signOut() async {
        session = nil
        KeychainStore.delete(key: Self.sessionKey)
    }

    // MARK: GoTrue plumbing

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: String
            let email: String?
        }

        let accessToken: String
        let refreshToken: String
        let expiresIn: Double?
        let expiresAt: Double?
        let user: User
    }

    private func adopt(tokenData: Data) throws -> AuthSession {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let token = try decoder.decode(TokenResponse.self, from: tokenData)
        let expiry = token.expiresAt.map(Date.init(timeIntervalSince1970:))
            ?? Date().addingTimeInterval(token.expiresIn ?? 3600)
        let adopted = AuthSession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: expiry,
            userID: token.user.id,
            email: token.user.email
        )
        session = adopted
        if let data = try? JSONEncoder().encode(adopted) {
            KeychainStore.save(data, key: Self.sessionKey)
        }
        return adopted
    }

    private func call(path: String, body: [String: Any]) async throws -> Data {
        // Composed with URL(string:relativeTo:) because appendingPathComponent
        // would percent-escape the "?" in the refresh grant path.
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AuthError.unreachable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AuthError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.unreachable }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.service(Self.message(from: data, status: http.statusCode))
        }
        return data
    }

    /// GoTrue error payloads vary; surface the most human field available.
    private static func message(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["msg", "message", "error_description"] {
                if let value = json[key] as? String, !value.isEmpty { return value }
            }
        }
        if status == 429 {
            return "Too many attempts for now. Wait a minute and try again."
        }
        return "Sign in failed. Try again."
    }
}
