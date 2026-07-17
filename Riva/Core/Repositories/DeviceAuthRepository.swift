import Foundation

/// Interim identity while the product has no sign-in screen: a stable
/// random device id (kept in the Keychain) is exchanged with the scan
/// service for a session backing a silently provisioned account.
///
/// The email code path of `AuthRepository` is intentionally disabled here;
/// when the landing page design lands, `AppDependencies` swaps this back
/// to `SupabaseAuthRepository` and nothing else changes.
actor DeviceAuthRepository: AuthRepository {

    private static let sessionKey = "device.session"
    private static let deviceIDKey = "device.id"

    private let scanServiceURL: URL
    private let urlSession: URLSession
    private var session: AuthSession?

    init(scanServiceURL: URL = BackendEnvironment.scanServiceURL) {
        self.scanServiceURL = scanServiceURL
        let config = URLSessionConfiguration.ephemeral
        // Generous: the free tier host sleeps and takes up to a minute to wake.
        config.timeoutIntervalForRequest = 120
        urlSession = URLSession(configuration: config)
        if let data = KeychainStore.load(key: Self.sessionKey) {
            session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
        #if DEBUG
        // Test hook: inject a session so automated runs control identity.
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
        throw AuthError.service("Email sign in is not enabled yet.")
    }

    @discardableResult
    func verifyCode(email: String, code: String) async throws -> AuthSession {
        throw AuthError.service("Email sign in is not enabled yet.")
    }

    func validAccessToken() async throws -> String? {
        if let session, session.isFresh { return session.accessToken }
        return try await provision().accessToken
    }

    func signOut() async {
        session = nil
        KeychainStore.delete(key: Self.sessionKey)
    }

    // MARK: Provisioning

    private struct DeviceSessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Double?
        let userId: String
        let email: String
    }

    private func provision() async throws -> AuthSession {
        var request = URLRequest(url: scanServiceURL.appending(path: "v1/device/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["device_id": deviceID()])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AuthError.unreachable
        }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AuthError.service("Could not set up this device. Try again.")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(DeviceSessionResponse.self, from: data)
        let adopted = AuthSession(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken ?? "",
            expiresAt: payload.expiresAt.map(Date.init(timeIntervalSince1970:))
                ?? Date().addingTimeInterval(3600),
            userID: payload.userId,
            email: payload.email
        )
        session = adopted
        if let encoded = try? JSONEncoder().encode(adopted) {
            KeychainStore.save(encoded, key: Self.sessionKey)
        }
        return adopted
    }

    /// Stable random id for this device, minted once and kept in the
    /// Keychain (it survives app reinstalls).
    private func deviceID() -> String {
        if let data = KeychainStore.load(key: Self.deviceIDKey),
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString.lowercased()
        KeychainStore.save(Data(id.utf8), key: Self.deviceIDKey)
        return id
    }
}
