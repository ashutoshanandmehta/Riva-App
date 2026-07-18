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
                ProfileView(
                    account: dependencies.accountRepository,
                    auth: dependencies.authRepository
                )
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
        .sheet(item: $appModel.activeAccountSheet) { sheet in
            accountSheet(for: sheet)
        }
        .sheet(item: $appModel.activeDetail) { detail in
            detailScreen(for: detail)
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

    // MARK: Account sheets and details

    @ViewBuilder
    private func accountSheet(for sheet: AccountSheet) -> some View {
        let close = { appModel.activeAccountSheet = nil }
        switch sheet {
        case .editProfile:
            EditProfileSheet(account: dependencies.accountRepository, onClose: close)
        case .editGoals:
            EditGoalsSheet(account: dependencies.accountRepository, onClose: close)
        case .doseSettings:
            DoseSettingsSheet(account: dependencies.accountRepository, onClose: close)
        case .injectionDay:
            InjectionDaySheet(account: dependencies.accountRepository, onClose: close)
        case .siteRotation:
            SiteRotationSheet(account: dependencies.accountRepository, onClose: close)
        case .notifications:
            NotificationsSheet(account: dependencies.accountRepository, onClose: close)
        case .privacy:
            PrivacySheet(
                account: dependencies.accountRepository,
                auth: dependencies.authRepository,
                onClose: close
            )
        }
    }

    @ViewBuilder
    private func detailScreen(for detail: DetailScreen) -> some View {
        let close = { appModel.activeDetail = nil }
        switch detail {
        case .shotHistory:
            ShotHistoryView(account: dependencies.accountRepository, onClose: close)
        case .weightHistory:
            WeightHistoryView(account: dependencies.accountRepository, onClose: close)
        case .sideEffectsHistory:
            SideEffectsHistoryView(account: dependencies.accountRepository, onClose: close)
        case .curveInfo:
            CurveInfoSheet(onClose: close)
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
