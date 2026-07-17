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

    /// Production wiring. The scanner is live against the Riva backend;
    /// dashboards are still mock-backed until their APIs exist.
    ///
    /// Identity is currently a silent per-device account (no sign-in
    /// screen). When the landing page design lands, swap this back to
    /// `SupabaseAuthRepository()` and restore the auth gate in `RivaApp`.
    static func live() -> AppDependencies {
        let auth = DeviceAuthRepository()
        return AppDependencies(
            homeRepository: MockHomeRepository(),
            medicationRepository: MockMedicationRepository(),
            trackerRepository: MockTrackerRepository(),
            profileRepository: MockProfileRepository(),
            authRepository: auth,
            scanRepository: APIScanRepository(auth: auth),
            logRepository: APILogRepository(auth: auth)
        )
    }
}
