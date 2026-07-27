import SwiftUI

/// Profile and settings, presented from the gear button on any tab; slides
/// over the tab content while the tab bar stays visible.
struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthModel.self) private var authModel
    @State private var viewModel: ProfileViewModel
    @State private var isStartFreshPresented = false
    @State private var isLogOutPresented = false

    init(account: any AccountRepository) {
        _viewModel = State(initialValue: ProfileViewModel(account: account))
    }

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .loading:
                LoadingStateView(message: "Loading your profile…")
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await viewModel.load() }
                }
            case .loaded(let bundle):
                content(bundle)
            }
        }
        .background(TPCColor.background)
        .contentMargins(.bottom, TPCLayout.tabBarClearance, for: .scrollContent)
        .task { await viewModel.load() }
        .onChange(of: appModel.activeAccountSheet) { previous, current in
            // Refresh after a settings sheet closes so edits show right away.
            if previous != nil, current == nil {
                Task { await viewModel.load() }
            }
        }
    }

    // MARK: Loaded

    private func content(_ bundle: AccountBundle) -> some View {
        LazyVStack(alignment: .leading, spacing: TPCSpacing.md) {
            BrandTopBar(onBack: { appModel.closeProfile() }, onSettings: nil)

            ProfileHeader(name: bundle.profile.name) {
                appModel.activeAccountSheet = .editProfile
            }

            PersonalGoalsSection(
                startWeightLbs: bundle.profile.startWeight,
                goalWeightLbs: bundle.profile.goalWeight
            ) {
                appModel.activeAccountSheet = .editGoals
            }

            DailyTargetsCard(goals: bundle.nutritionGoals)

            medicationSettings(bundle.plan)

            appearanceSection

            accountSection

            dangerZone

            Text(Self.versionFooter)
                .font(.system(size: 11))
                .foregroundStyle(TPCColor.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.top, TPCSpacing.xs)
    }

    // MARK: Medication settings

    private func medicationSettings(_ plan: MedicationPlan?) -> some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            Text("Medication settings")
                .rivaOverline()

            VStack(spacing: TPCSpacing.xs) {
                SettingsRow(
                    systemImage: "syringe",
                    title: plan?.name ?? "Medication",
                    subtitle: plan.map {
                        "Current Dose: \(RivaFormat.doseMgCompact($0.currentDoseMg))"
                    } ?? "Set your medication and dose"
                ) {
                    appModel.activeAccountSheet = .doseSettings
                }
                SettingsRow(
                    systemImage: "calendar",
                    title: "Injection Day",
                    subtitle: plan?.reminderDescription ?? "Choose your weekly day"
                ) {
                    appModel.activeAccountSheet = .injectionDay
                }
                SettingsRow(
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    title: "Site Rotation",
                    subtitle: "Where to inject next"
                ) {
                    appModel.activeAccountSheet = .siteRotation
                }
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        @Bindable var appModel = appModel
        return VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            Text("Appearance")
                .rivaOverline()

            RivaCard {
                VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                    HStack(spacing: TPCSpacing.sm) {
                        RivaIconChip(systemImage: "circle.lefthalf.filled", size: 34)
                        Text("Theme")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TPCColor.textPrimary)
                        Spacer()
                    }

                    Picker("Appearance", selection: $appModel.appearance) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            Text("Account")
                .rivaOverline()

            VStack(spacing: TPCSpacing.xs) {
                SettingsRow(systemImage: "bell", title: "Notifications", subtitle: nil) {
                    appModel.activeAccountSheet = .notifications
                }
                SettingsRow(systemImage: "lock", title: "Privacy & Security", subtitle: nil) {
                    appModel.activeAccountSheet = .privacy
                }
                SettingsRow(
                    systemImage: "rectangle.portrait.and.arrow.right",
                    title: "Log Out",
                    subtitle: nil
                ) {
                    isLogOutPresented = true
                }
                .confirmationDialog(
                    "Log out?",
                    isPresented: $isLogOutPresented,
                    titleVisibility: .visible
                ) {
                    Button("Log Out", role: .destructive) {
                        Task {
                            appModel.closeProfile()
                            await authModel.signOut()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You can sign back in anytime; your data stays saved.")
                }
            }
        }
    }

    // MARK: Danger zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.sm) {
            Text("Danger Zone")
                .rivaOverline(TPCColor.danger)

            Button {
                isStartFreshPresented = true
            } label: {
                HStack(spacing: TPCSpacing.xs) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Start Fresh")
                }
            }
            .buttonStyle(.rivaDestructive)
            .confirmationDialog(
                "Start fresh?",
                isPresented: $isStartFreshPresented,
                titleVisibility: .visible
            ) {
                Button("Erase & Start Fresh", role: .destructive) {
                    Task {
                        appModel.closeProfile()
                        await authModel.startFresh()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently erases all your logged data and starts a brand-new profile. This cannot be undone.")
            }
        }
    }

    /// "The Peptide Company Version 0.1.0 (Build 1)", read from the bundle so it can
    /// never drift from the shipped binary.
    private static var versionFooter: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "The Peptide Company Version \(version) (Build \(build))"
    }
}

#Preview {
    ProfileView(account: MockAccountRepository())
        .environment(AppModel())
        .environment(AuthModel(repository: MockAuthRepository(), account: MockAccountRepository()))
}
