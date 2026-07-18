import Foundation

/// Composition root for the app's data layer.
///
/// Every repository the app uses is constructed exactly once, here.
/// Features receive dependencies through initializers, never by reaching for
/// singletons — which keeps them previewable and unit-testable with fakes.
struct AppDependencies {
    let homeRepository: any HomeRepository
    let medicationRepository: any MedicationRepository
    let trackerRepository: any TrackerRepository
    let profileRepository: any ProfileRepository
    let authRepository: any AuthRepository
    let scanRepository: any ScanRepository
    let logRepository: any LogRepository
    let accountRepository: any AccountRepository

    /// Production wiring: everything reads and writes the Riva backend.
    /// Mock repositories exist only for previews.
    ///
    /// Identity: Google sign in through Supabase (the onboarding gate in
    /// RivaApp). DeviceAuthRepository remains available for reviving the
    /// no-sign-in mode if ever needed.
    static func live() -> AppDependencies {
        let auth = SupabaseAuthRepository()
        let dashboards = DashboardService(auth: auth)
        return AppDependencies(
            homeRepository: APIHomeRepository(service: dashboards),
            medicationRepository: APIMedicationRepository(service: dashboards),
            trackerRepository: APITrackerRepository(service: dashboards),
            profileRepository: MockProfileRepository(),
            authRepository: auth,
            scanRepository: APIScanRepository(auth: auth),
            logRepository: APILogRepository(auth: auth),
            accountRepository: APIAccountRepository(auth: auth)
        )
    }
}
