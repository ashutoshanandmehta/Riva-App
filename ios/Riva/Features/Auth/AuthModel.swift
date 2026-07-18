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
        /// "What brings you to Riva?" goal selection, then account creation.
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

            if fromLogin {
                let bundle = try? await account.me()
                let untouched = (bundle?.profile.name ?? "there") == "there"
                    && bundle?.profile.goalWeight == nil
                stage = untouched ? .completingProfile : .signedIn
            } else {
                if !selectedGoals.isEmpty {
                    try? await account.updateHealthGoals(HealthGoalsUpdate(selected: selectedGoals))
                }
                stage = .completingProfile
            }
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
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
