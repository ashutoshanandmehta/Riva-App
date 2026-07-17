import Foundation

/// Data source for the Tracker tab.
///
/// UI code depends only on this protocol; swap `MockTrackerRepository`
/// for an API-backed implementation in `AppDependencies` when the backend
/// is ready.
protocol TrackerRepository: Sendable {
    func trackerDashboard() async throws -> TrackerDashboard
    func weeklySummary() async throws -> WeeklySummary
}
