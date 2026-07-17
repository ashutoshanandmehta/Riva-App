import Foundation

/// Data source for the Home dashboard.
///
/// UI code depends only on this protocol. Today the app ships with
/// `MockHomeRepository`; when the backend is ready, add an
/// `APIHomeRepository` conforming to this protocol and swap it in
/// `AppDependencies` — no view or view-model changes required.
protocol HomeRepository: Sendable {
    func homeSnapshot() async throws -> HomeSnapshot
}
