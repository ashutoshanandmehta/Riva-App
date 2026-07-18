import SwiftUI

/// Profile and settings, presented from the gear button on any tab; slides
/// over the tab content while the tab bar stays visible.
struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: ProfileViewModel
    @State private var isStartFreshPresented = false

    private let auth: any AuthRepository

    init(account: any AccountRepository, auth: any AuthRepository) {
        self.auth = auth
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
        .background(RivaColor.background)
        .contentMargins(.bottom, RivaLayout.tabBarClearance, for: .scrollContent)
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
        LazyVStack(alignment: .leading, spacing: RivaSpacing.md) {
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

            Button {
                isStartFreshPresented = true
            } label: {
                HStack(spacing: RivaSpacing.xs) {
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
                Button("Start Fresh", role: .destructive) {
                    Task {
                        await auth.resetIdentity()
                        appModel.closeProfile()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This unlinks this device's data and starts a new profile.")
            }

            Text(Self.versionFooter)
                .font(.system(size: 11))
                .foregroundStyle(RivaColor.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
    }

    // MARK: Medication settings

    private func medicationSettings(_ plan: MedicationPlan?) -> some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            Text("Medication settings")
                .rivaOverline()

            VStack(spacing: RivaSpacing.xs) {
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
        return VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            Text("Appearance")
                .rivaOverline()

            RivaCard {
                VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                    HStack(spacing: RivaSpacing.sm) {
                        RivaIconChip(systemImage: "circle.lefthalf.filled", size: 34)
                        Text("Theme")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(RivaColor.textPrimary)
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
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            Text("Account")
                .rivaOverline()

            VStack(spacing: RivaSpacing.xs) {
                SettingsRow(systemImage: "bell", title: "Notifications", subtitle: nil) {
                    appModel.activeAccountSheet = .notifications
                }
                SettingsRow(systemImage: "lock", title: "Privacy & Security", subtitle: nil) {
                    appModel.activeAccountSheet = .privacy
                }
            }
        }
    }

    /// "Riva App Version 0.1.0 (Build 1)", read from the bundle so it can
    /// never drift from the shipped binary.
    private static var versionFooter: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Riva App Version \(version) (Build \(build))"
    }
}

#Preview {
    ProfileView(account: MockAccountRepository(), auth: MockAuthRepository())
        .environment(AppModel())
}
