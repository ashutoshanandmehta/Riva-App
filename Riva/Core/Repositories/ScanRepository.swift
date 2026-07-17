import Foundation

/// The food and water scanner: one photo in, a structured result out, and a
/// server-authoritative log on Accept.
protocol ScanRepository: Sendable {
    /// Sends a JPEG to the scan pipeline. `mode` is the user's intent hint
    /// (auto, food, water); the result always describes the actual content.
    func scan(imageData: Data, mode: ScanMode) async throws -> ScanResult

    /// Persists an accepted scan and returns the day's updated totals.
    func accept(_ scan: ScanResult) async throws -> DayTotals
}

enum ScanServiceError: LocalizedError {
    /// No session, or the backend rejected the token. Show sign-in.
    case signInRequired
    case service(String)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .signInRequired: "Sign in to continue."
        case .service(let message): message
        case .unreachable: "Could not reach the scan service. Check your connection and try again."
        }
    }
}
