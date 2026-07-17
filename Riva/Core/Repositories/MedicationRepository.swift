import Foundation

/// Data source for the Medication tab.
///
/// UI code depends only on this protocol; swap `MockMedicationRepository`
/// for an API-backed implementation in `AppDependencies` when the backend
/// is ready.
protocol MedicationRepository: Sendable {
    func medicationDashboard() async throws -> MedicationDashboard
}
