import SwiftUI

/// App scaffold: hosts the tab content, the floating Liquid Glass tab bar,
/// the radial snap menu, and the shared placeholder sheet.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    let dependencies: AppDependencies

    var body: some View {
        @Bindable var appModel = appModel

        ZStack(alignment: .bottom) {
            tabContent

            // Profile slides in over the tab content, keeping the tab bar
            // visible (drawn later in this ZStack).
            if appModel.isProfilePresented {
                ProfileView(repository: dependencies.profileRepository)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Dim the content while the snap menu is open; tap to dismiss.
            if appModel.isSnapMenuOpen {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { appModel.closeSnapMenu() }
            }

            VStack(spacing: 0) {
                SnapRadialFan(isOpen: appModel.isSnapMenuOpen) { action in
                    appModel.open(snapAction: action)
                }
                RivaTabBar()
            }
            .padding(.bottom, RivaSpacing.xs)
        }
        .background(RivaColor.background)
        .sheet(item: $appModel.activePlaceholder) { context in
            PlaceholderSheet(context: context)
        }
        .sheet(item: $appModel.activeQuickLog) { kind in
            QuickLogSheet(kind: kind, repository: dependencies.logRepository) {
                appModel.activeQuickLog = nil
            }
        }
        .fullScreenCover(item: $appModel.activeScanMode) { mode in
            SnapScanView(
                mode: mode,
                scanRepository: dependencies.scanRepository
            ) {
                appModel.activeScanMode = nil
            }
        }
    }

    /// All tabs stay mounted so per-tab state (scroll position, loaded data)
    /// survives switching — matching platform TabView behavior.
    private var tabContent: some View {
        ZStack {
            tabPage(.home) {
                HomeView(repository: dependencies.homeRepository)
            }
            tabPage(.wellness) { WellnessView() }
            tabPage(.medication) {
                MedicationView(repository: dependencies.medicationRepository)
            }
            tabPage(.tracker) {
                TrackerView(repository: dependencies.trackerRepository)
            }
        }
    }

    @ViewBuilder
    private func tabPage(_ tab: AppTab, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = appModel.selectedTab == tab
        content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

#Preview {
    RootView(dependencies: .live())
        .environment(AppModel())
}
