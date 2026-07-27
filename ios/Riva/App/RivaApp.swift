import SwiftUI

@main
struct RivaApp: App {
    /// App-wide UI state (selected tab, snap menu, placeholder sheets).
    @State private var appModel = AppModel()
    /// The front door: landing, onboarding, Google sign in, profile
    /// completion. Everything inside the app assumes a session.
    @State private var authModel: AuthModel
    /// Composition root — swap mock repositories for API-backed ones here.
    private let dependencies: AppDependencies

    init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        _authModel = State(initialValue: AuthModel(
            repository: dependencies.authRepository,
            account: dependencies.accountRepository
        ))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch authModel.stage {
                case .checking:
                    // Looking up the stored session; sub-second.
                    ZStack {
                        TPCColor.background.ignoresSafeArea()
                        ProgressView()
                    }
                case .landing:
                    LandingView(model: authModel)
                case .onboarding:
                    GoalsStepView(model: authModel)
                case .login:
                    LoginView(model: authModel)
                case .emailLogin:
                    EmailLoginView(model: authModel)
                case .emailFlow(let flow):
                    EmailFlowView(model: authModel, flow: flow)
                case .completingProfile:
                    CompleteProfileView(model: authModel)
                case .signedIn:
                    ZStack {
                        RootView(dependencies: dependencies)
                            .environment(appModel)
                            .environment(authModel)

                        if let name = authModel.welcomeBackName {
                            WelcomeBackView(name: name) {
                                authModel.dismissWelcomeBack()
                            }
                            .transition(.opacity)
                            .zIndex(1)
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: authModel.welcomeBackName)
                }
            }
            .task { await authModel.start() }
            .tint(TPCColor.brand)
            // User-selected theme; `nil` (System) follows the device.
            .preferredColorScheme(appModel.appearance.colorScheme)
            // The "3D scan (beta)" ARKit capture flow now has real in-app
            // routing from the signed-in Snap tab (see `RootView`) instead
            // of a pre-auth cover here. `-riva.volumetric` still launches
            // straight into it post-sign-in via `AppModel`.
        }
    }
}
