import AuthenticationServices
import CryptoKit
import Foundation
import Observation

/// The front door state machine: landing page, onboarding goals, sign in
/// (Google, Apple, or email + password), profile completion, then the app.
/// The user signs in exactly once; the session persists in the Keychain.
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
        /// Returning user: the provider buttons.
        case login
        /// Returning user typing an email and password.
        case emailLogin
        /// The three-step email wizard, for creating an account or re-keying one.
        case emailFlow(EmailFlow)
        /// Right after account creation: profile details.
        case completingProfile
        case signedIn
    }

    /// The two email journeys are the same three steps — enter an address,
    /// confirm the six digit code, choose a password. Sign-up creates the
    /// account on the way through; reset re-keys one that already exists.
    enum EmailFlow: Equatable {
        case signUp
        case reset

        var title: String {
            switch self {
            case .signUp: "Create your account"
            case .reset: "Reset your password"
            }
        }
    }

    enum EmailStep: Equatable {
        case address
        case code
        case password
    }

    private(set) var stage: Stage = .checking
    private(set) var isWorking = false
    private(set) var notice: String?

    /// Where the email wizard has got to.
    private(set) var emailStep: EmailStep = .address

    /// The address the in-flight code went to. Shown on the code screen and
    /// reused for the verify call, so the user cannot edit it out from under us.
    private(set) var pendingEmail = ""

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
        //   |email|emailcode|emailpassword|emaillogin|reset
        if let forced = UserDefaults.standard.string(forKey: "riva.auth") {
            switch forced {
            case "goals": stage = .onboarding
            case "login": stage = .login
            case "profile": stage = .completingProfile
            case "email":
                stage = .emailFlow(.signUp)
            case "emailcode":
                pendingEmail = "user@example.com"
                emailStep = .code
                stage = .emailFlow(.signUp)
            case "emailpassword":
                pendingEmail = "user@example.com"
                emailStep = .password
                stage = .emailFlow(.signUp)
            case "emaillogin": stage = .emailLogin
            case "reset": stage = .emailFlow(.reset)
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

    /// Create an account with an email address: code first, then a password.
    func startEmailSignUp() {
        notice = nil
        pendingEmail = ""
        emailStep = .address
        stage = .emailFlow(.signUp)
    }

    /// Returning user, typing an email and password.
    func showEmailLogin() {
        notice = nil
        stage = .emailLogin
    }

    /// "Forgot password?" — the same wizard, re-keying an existing account.
    func startPasswordReset() {
        notice = nil
        pendingEmail = ""
        emailStep = .address
        stage = .emailFlow(.reset)
    }

    /// Back button for the email screens: retreat one step inside the wizard,
    /// or leave it from the first step.
    ///
    /// Backing out of the password step is an abandon, not a retreat: the code
    /// has already been spent for a session, so there is nothing to return to.
    func backFromEmail() async {
        notice = nil
        switch stage {
        case .emailLogin:
            stage = .login
        case .emailFlow(let flow):
            switch emailStep {
            case .address:
                stage = flow == .signUp ? .onboarding : .emailLogin
            case .code:
                emailStep = .address
            case .password:
                await repository.signOut()
                pendingEmail = ""
                emailStep = .address
                stage = flow == .signUp ? .landing : .login
                notice = "You'll need a new code to finish that."
            }
        default:
            stage = .landing
        }
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

    // MARK: Email + password

    /// Step one: send a six digit code to `email`.
    ///
    /// Sign-up uses GoTrue's OTP grant (which creates the account on first
    /// use); reset uses the recovery grant. Recovery deliberately reports
    /// success for addresses that don't exist, so an attacker cannot use this
    /// screen to discover who has an account.
    func submitEmail(_ email: String) async {
        guard !isWorking, case .emailFlow(let flow) = stage else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isPlausibleEmail(address) else {
            notice = "That doesn't look like an email address."
            return
        }

        isWorking = true
        notice = nil
        do {
            switch flow {
            case .signUp: try await repository.requestCode(email: address)
            case .reset: try await repository.requestPasswordReset(email: address)
            }
            pendingEmail = address
            emailStep = .code
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    /// Re-sends the code to `pendingEmail` without leaving the code screen.
    func resendCode() async {
        guard !isWorking, case .emailFlow(let flow) = stage, !pendingEmail.isEmpty else { return }
        isWorking = true
        notice = nil
        do {
            switch flow {
            case .signUp: try await repository.requestCode(email: pendingEmail)
            case .reset: try await repository.requestPasswordReset(email: pendingEmail)
            }
            notice = "Sent another code to \(pendingEmail)."
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    /// Step two: exchange the code for a session. That session is what lets
    /// step three set a password, so this must succeed before the password
    /// screen appears.
    func submitCode(_ code: String) async {
        guard !isWorking, case .emailFlow(let flow) = stage else { return }
        let token = code.filter(\.isNumber)
        guard token.count == Self.codeLength else {
            notice = "Enter the \(Self.codeLength) digit code from your email."
            return
        }

        isWorking = true
        notice = nil
        do {
            switch flow {
            case .signUp:
                try await repository.verifyCode(email: pendingEmail, code: token)
            case .reset:
                try await repository.verifyPasswordReset(email: pendingEmail, code: token)
            }
            emailStep = .password
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    /// Step three: set the password on the session the code just produced.
    ///
    /// Sign-up carries on to profile completion; a reset drops the user
    /// straight into the app, since they already have one.
    func submitPassword(_ password: String, confirmation: String) async {
        guard !isWorking, case .emailFlow(let flow) = stage else { return }
        guard password == confirmation else {
            notice = "Those two passwords don't match."
            return
        }
        let assessment = PasswordPolicy.assess(password, email: pendingEmail)
        guard assessment.isAcceptable else {
            notice = assessment.problem ?? "Pick a stronger password."
            return
        }

        isWorking = true
        notice = nil
        do {
            try await repository.updatePassword(password)
            await routeAfterSignIn(fromLogin: flow == .reset)
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    /// Returning user signing in with an address and password.
    func signInWithEmail(email: String, password: String) async {
        guard !isWorking else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isPlausibleEmail(address), !password.isEmpty else {
            notice = "Enter your email and password."
            return
        }

        isWorking = true
        notice = nil
        do {
            try await repository.signIn(email: address, password: password)
            await routeAfterSignIn(fromLogin: true)
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    /// GoTrue emails six digits.
    static let codeLength = 6

    /// Deliberately loose: the code we email is the real check, so this only
    /// catches typos before spending a send.
    static func isPlausibleEmail(_ address: String) -> Bool {
        guard !address.contains(" "), address.count >= 6 else { return false }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
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
