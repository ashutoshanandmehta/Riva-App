import SwiftUI

/// Profile & settings — presented from the gear button on any tab; slides
/// over the tab content while the tab bar stays visible.
struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: ProfileViewModel

    init(repository: any ProfileRepository) {
        _viewModel = State(initialValue: ProfileViewModel(repository: repository))
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
            case .loaded(let profile):
                content(profile)
            }
        }
        .background(RivaColor.background)
        .contentMargins(.bottom, RivaLayout.tabBarClearance, for: .scrollContent)
        .task { await viewModel.load() }
    }

    // MARK: Loaded

    private func content(_ profile: ProfileSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: RivaSpacing.md) {
            BrandTopBar(onBack: { appModel.closeProfile() }, onSettings: nil)

            ProfileHeader(profile: profile) {
                appModel.present(placeholder: .editProfile)
            }

            PersonalGoalsSection(goals: profile.goals) {
                appModel.present(placeholder: .editGoals)
            }

            DailyTargetsCard(calories: profile.calories, protein: profile.protein)

            medicationSettings(profile.medication)

            appearanceSection

            accountSection

            Button {
                appModel.present(placeholder: .logOut)
            } label: {
                HStack(spacing: RivaSpacing.xs) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Log Out")
                }
            }
            .buttonStyle(.rivaDestructive)

            Text(Self.versionFooter)
                .font(.system(size: 11))
                .foregroundStyle(RivaColor.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.top, RivaSpacing.xs)
    }

    // MARK: Medication settings

    private func medicationSettings(_ medication: MedicationSettings) -> some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            Text("Medication settings")
                .rivaOverline()

            VStack(spacing: RivaSpacing.xs) {
                SettingsRow(
                    systemImage: "syringe",
                    title: medication.drugName,
                    subtitle: "Current Dose: \(RivaFormat.doseMgCompact(medication.currentDoseMg))"
                ) {
                    appModel.present(placeholder: .doseSettings)
                }
                SettingsRow(
                    systemImage: "calendar",
                    title: "Injection Day",
                    subtitle: medication.injectionDaySummary
                ) {
                    appModel.present(placeholder: .injectionDaySettings)
                }
                SettingsRow(
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    title: "Site Rotation",
                    subtitle: "Current: \(medication.currentSite)"
                ) {
                    appModel.present(placeholder: .siteRotationSettings)
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
                    appModel.present(placeholder: .notifications)
                }
                SettingsRow(systemImage: "lock", title: "Privacy & Security", subtitle: nil) {
                    appModel.present(placeholder: .privacySecurity)
                }
            }
        }
    }

    /// "Riva App Version 0.1.0 (Build 1)" — read from the bundle so it can
    /// never drift from the shipped binary.
    private static var versionFooter: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Riva App Version \(version) (Build \(build))"
    }
}

#Preview {
    ProfileView(repository: MockProfileRepository())
        .environment(AppModel())
}
