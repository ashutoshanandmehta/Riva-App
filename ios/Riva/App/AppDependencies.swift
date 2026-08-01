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
    let authRepository: any AuthRepository
    let scanRepository: any ScanRepository
    /// Backs the inline item editor on the scan result card: replacements for
    /// a food the scan read wrongly, so a correction costs no second scan.
    let foodReplacementService: any FoodReplacementService
    let logRepository: any LogRepository
    let accountRepository: any AccountRepository
    let wellnessRepository: any WellnessRepository
    /// Backs the to-do card on Home. Its own endpoints rather than the shared
    /// dashboard fetch, because to-dos are written as well as read.
    let todoRepository: any TodoRepository
    /// Backs the "3D scan (beta)" ARKit volumetric capture flow in the Snap
    /// tab. Anonymous/stateless, like `scanRepository.scan` — persisting an
    /// accepted volumetric scan reuses `scanRepository.accept`, not a
    /// separate endpoint.
    let volumetricScanRepository: any VolumetricScanRepository
    /// Backs the AI companion tab. Conversation state lives server-side; the
    /// client only holds the thread id it was given.
    let companionRepository: any CompanionRepository

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
            authRepository: auth,
            scanRepository: APIScanRepository(auth: auth),
            foodReplacementService: APIFoodReplacementService(auth: auth),
            logRepository: APILogRepository(auth: auth),
            accountRepository: APIAccountRepository(auth: auth),
            wellnessRepository: APIWellnessRepository(service: dashboards, auth: auth),
            todoRepository: APITodoRepository(auth: auth),
            volumetricScanRepository: APIVolumetricScanRepository(),
            companionRepository: APICompanionRepository(auth: auth)
        )
    }
}
