import Foundation

/// Data source for the Profile screen.
///
/// UI code depends only on this protocol; swap `MockProfileRepository`
/// for an API-backed implementation in `AppDependencies` when the backend
/// is ready.
protocol ProfileRepository: Sendable {
    func profile() async throws -> ProfileSnapshot
}
