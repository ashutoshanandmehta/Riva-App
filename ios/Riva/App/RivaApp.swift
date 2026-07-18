import SwiftUI

@main
struct RivaApp: App {
    /// App-wide UI state (selected tab, snap menu, placeholder sheets).
    @State private var appModel = AppModel()
    /// Composition root — swap mock repositories for API-backed ones here.
    private let dependencies = AppDependencies.live()

    // No sign-in screen in this phase: identity is a silent per-device
    // account (see DeviceAuthRepository). The landing page gate returns
    // here together with its design.
    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .environment(appModel)
                .tint(RivaColor.brand)
                // User-selected theme; `nil` (System) follows the device.
                .preferredColorScheme(appModel.appearance.colorScheme)
        }
    }
}
