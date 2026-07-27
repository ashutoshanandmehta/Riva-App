import AuthenticationServices
import CryptoKit
import Foundation
import Observation

/// The front door state machine: landing page, onboarding goals, Google
/// sign in (create or log in), profile completion, then the app. The user
/// signs in exactly once; the session persists in the Keychain.
@MainActor
@Observable
final class AuthModel {

    enum Stage: Equatable {
        /// Looking for a stored session at launch.
        case checking
        /// The marketing landing page.
        case landing
        /// "What brings you to The Peptide Company?" goal selection, then account creation.
        case onboarding
        /// Returning user: straight to Google sign in.
        case login
        /// Right after account creation: profile details.
        case completingProfile
        case signedIn
    }

    private(set) var stage: Stage = .checking
    private(set) var isWorking = false
    private(set) var notice: String?

    /// Set right after a returning login so the app can show a brief
    /// "Welcome back" splash. Empty string = greet without a name; nil = no
    /// splash pending.
    private(set) var welcomeBackName: String?

    /// Goals picked during onboarding, saved right after account creation.
    var selectedGoals: Set<OnboardingGoal> = []

    private let repository: any AuthRepository
    private let account: any AccountRepository
    private let webAuth = WebAuthSession()

    init(repository: any AuthRepository, account: any AccountRepository) {
        self.repository = repository
        self.account = account
    }

    func start() async {
        guard stage == .checking else { return }
        #if DEBUG
        // Screenshot hook: -riva.auth landing|goals|login|profile
        if let forced = UserDefaults.standard.string(forKey: "riva.auth") {
            switch forced {
            case "goals": stage = .onboarding
            case "login": stage = .login
            case "profile": stage = .completingProfile
            default: stage = .landing
            }
            return
        }
        #endif
        stage = await repository.currentSession() == nil ? .landing : .signedIn
    }

    // MARK: Navigation

    func getStarted() {
        notice = nil
        stage = .onboarding
    }

    func showLogin() {
        notice = nil
        stage = .login
    }

    func backToLanding() {
        notice = nil
        stage = .landing
    }

    // MARK: Sign out / reset

    /// Signs out of this device's session but keeps the account. Returns to
    /// the front door; signing back in restores the same data.
    func signOut() async {
        await repository.signOut()
        selectedGoals = []
        notice = nil
        stage = .landing
    }

    /// Wipes the user's data and this device's identity, then returns to the
    /// front door for a brand-new start. Best-effort: even if the server-side
    /// delete fails, the local session is still cleared.
    func startFresh() async {
        try? await account.deleteAccount()
        await repository.resetIdentity()
        selectedGoals = []
        notice = nil
        stage = .landing
    }

    /// Clears the pending "Welcome back" splash once it has been shown.
    func dismissWelcomeBack() {
        welcomeBackName = nil
    }

    func toggle(_ goal: OnboardingGoal) {
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else {
            selectedGoals.insert(goal)
        }
    }

    // MARK: Google sign in

    /// Runs the Google OAuth flow. Account creation continues to profile
    /// completion (and saves the picked goals); a returning login goes
    /// straight in unless the profile is clearly untouched.
    func continueWithGoogle(fromLogin: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        notice = nil
        do {
            let callback = try await webAuth.signIn(
                url: BackendEnvironment.googleAuthorizeURL,
                callbackScheme: BackendEnvironment.oauthCallbackScheme
            )
            try await repository.adoptOAuthCallback(callback)
            await routeAfterSignIn(fromLogin: fromLogin)
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    /// Where a completed sign-in lands, shared by every provider: returning
    /// users skip the profile form, new accounts go on to fill it in.
    private func routeAfterSignIn(fromLogin: Bool) async {
        if fromLogin {
            // A returning login never sees the profile-creation form. Go
            // straight in and greet them by name.
            let bundle = try? await account.me()
            let first = bundle?.profile.name
                .split(separator: " ").first.map(String.init)
            welcomeBackName = (first == nil || first == "there") ? "" : first
            stage = .signedIn
        } else {
            if !selectedGoals.isEmpty {
                try? await account.updateHealthGoals(HealthGoalsUpdate(selected: selectedGoals))
            }
            stage = .completingProfile
        }
    }

    // MARK: Sign in with Apple

    /// Raw nonce for the in-flight Apple request. Apple embeds its SHA256 in
    /// the identity token; Supabase needs the raw value to verify the pair.
    private var pendingAppleNonce: String?

    /// Called from the button's `onRequest`. Returns the hashed nonce to put
    /// on the request, keeping the raw one for the exchange afterwards.
    func prepareAppleNonce() -> String {
        let raw = Self.randomNonce()
        pendingAppleNonce = raw
        return Self.sha256(raw)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, any Error>, fromLogin: Bool) async {
        guard !isWorking else { return }

        switch result {
        case .failure(let error):
            // Dismissing the sheet is not a failure worth shouting about.
            if (error as? ASAuthorizationError)?.code != .canceled {
                notice = error.localizedDescription
            }
            pendingAppleNonce = nil
            return

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingAppleNonce else {
                notice = "Apple sign in did not complete. Try again."
                pendingAppleNonce = nil
                return
            }

            isWorking = true
            notice = nil
            do {
                try await repository.signInWithApple(idToken: idToken, nonce: nonce)
                await routeAfterSignIn(fromLogin: fromLogin)
            } catch {
                notice = error.localizedDescription
            }
            pendingAppleNonce = nil
            isWorking = false
        }
    }

    /// Apple requires an unguessable, single-use nonce per authorization.
    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else {
            // The CSPRNG failing is not recoverable; a predictable nonce would
            // silently weaken the exchange, so fail loudly instead.
            preconditionFailure("Unable to generate a secure nonce")
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: Profile completion

    func completeProfile(_ update: ProfileUpdate) async {
        guard !isWorking else { return }
        isWorking = true
        notice = nil
        do {
            _ = try await account.updateProfile(update)
            stage = .signedIn
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    func skipProfileForNow() {
        notice = nil
        stage = .signedIn
    }
}
