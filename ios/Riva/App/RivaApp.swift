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
                        RivaColor.background.ignoresSafeArea()
                        ProgressView()
                    }
                case .landing:
                    LandingView(model: authModel)
                case .onboarding:
                    GoalsStepView(model: authModel)
                case .login:
                    LoginView(model: authModel)
                case .completingProfile:
                    CompleteProfileView(model: authModel)
                case .signedIn:
                    RootView(dependencies: dependencies)
                        .environment(appModel)
                }
            }
            .task { await authModel.start() }
            .tint(RivaColor.brand)
            // User-selected theme; `nil` (System) follows the device.
            .preferredColorScheme(appModel.appearance.colorScheme)
        }
    }
}
