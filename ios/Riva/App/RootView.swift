import SwiftUI

/// App scaffold: tab content, floating Liquid Glass tab bar, + FAB, and
/// all shared sheets / full-screen covers.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    let dependencies: AppDependencies

    var body: some View {
        @Bindable var appModel = appModel

        ZStack(alignment: .bottom) {
            tabContent

            // Profile slides in over the tab content.
            if appModel.isProfilePresented {
                ProfileView(account: dependencies.accountRepository)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Dim the content while the FAB fan is open; tap to dismiss.
            if appModel.isFABOpen {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { appModel.closeFAB() }
            }

            // Tab bar + FAB stacked at the bottom
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    RivaTabBar()
                }
                .padding(.bottom, TPCSpacing.xs)

                TPCFloatingActionButton()
                    .padding(.trailing, 20)
                    .padding(.bottom, TPCLayout.tabBarHeight + TPCSpacing.sm)
            }
        }
        .background(TPCColor.background)
        .sheet(item: $appModel.activePlaceholder) { context in
            PlaceholderSheet(context: context)
        }
        .sheet(item: $appModel.activeQuickLog) { kind in
            QuickLogSheet(kind: kind, repository: dependencies.logRepository) { totals in
                appModel.activeQuickLog = nil
                appModel.applyLoggedTotals(totals)
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
                appModel.applyLoggedTotals(nil)
            }
        }
        .fullScreenCover(isPresented: $appModel.activeVolumetricScan) {
            ARFoodCaptureView(
                volumetricScanRepository: dependencies.volumetricScanRepository,
                accept: dependencies.scanRepository.accept
            ) {
                appModel.activeVolumetricScan = false
                appModel.applyLoggedTotals(nil)
            }
        }
    }

    /// All tabs stay mounted so per-tab scroll position and loaded data
    /// survive switching — matching platform TabView behaviour.
    private var tabContent: some View {
        ZStack {
            tabPage(.home) {
                HomeView(
                    repository: dependencies.homeRepository,
                    todoRepository: dependencies.todoRepository
                )
            }
            tabPage(.wellness) {
                WellnessView(
                    repository: dependencies.wellnessRepository,
                    logRepository: dependencies.logRepository,
                    account: dependencies.accountRepository
                )
            }
            tabPage(.companion) {
                CompanionView(repository: dependencies.companionRepository)
            }
            tabPage(.medication) {
                MedicationView(repository: dependencies.medicationRepository)
            }
            tabPage(.tracker) {
                TrackerView(repository: dependencies.trackerRepository)
            }
        }
    }

    // MARK: Account sheets

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

    // MARK: Detail screens

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
        case .caloriesHistory:
            NutritionHistoryView(
                metric: .calories, account: dependencies.accountRepository, onClose: close
            )
        case .hydrationHistory:
            NutritionHistoryView(
                metric: .hydration, account: dependencies.accountRepository, onClose: close
            )
        case .proteinHistory:
            NutritionHistoryView(
                metric: .protein, account: dependencies.accountRepository, onClose: close
            )
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
