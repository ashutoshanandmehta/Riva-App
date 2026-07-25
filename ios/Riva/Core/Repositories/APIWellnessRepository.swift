import Foundation

/// Live wellness repository: summary numbers ride the shared dashboard
/// fetch; suggestions come from `GET /v1/wellness/suggestions`. Both halves
/// fail soft — an old backend (no wellness block) or a suggestions error
/// degrades to zeros and the local time-of-day fallback, never a throw for
/// missing wellness support.
struct APIWellnessRepository: WellnessRepository {

    private let service: DashboardService
    private let baseURL: URL
    private let auth: any AuthRepository
    private let urlSession: URLSession

    init(
        service: DashboardService,
        auth: any AuthRepository,
        baseURL: URL = BackendEnvironment.scanServiceURL
    ) {
        self.service = service
        self.auth = auth
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        urlSession = URLSession(configuration: config)
    }

    func dashboard() async throws -> WellnessDashboard {
        async let suggestions = fetchSuggestions()
        let payload = try await service.fetch()
        return WellnessDashboard(
            summary: DashboardMapping.wellnessSummary(payload.wellness),
            suggestions: await suggestions,
            canLogSessions: payload.wellness != nil
        )
    }

    // MARK: Suggestions

    private struct SuggestionsWire: Decodable {
        struct Suggestion: Decodable {
            let practiceId: String
            let reason: String
        }
        let suggestions: [Suggestion]
    }

    /// Never throws: any transport, auth, or decode problem falls back to
    /// the local list so the tab always renders something helpful.
    private func fetchSuggestions() async -> [SuggestedPractice] {
        do {
            guard let token = try await auth.validAccessToken() else {
                return WellnessFallback.suggestions()
            }
            var request = URLRequest(url: baseURL.appending(path: "v1/wellness/suggestions"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return WellnessFallback.suggestions()
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let wire = try decoder.decode(SuggestionsWire.self, from: data)
            // Unknown catalog ids are dropped; an empty result falls back.
            let mapped = wire.suggestions.compactMap { suggestion in
                WellnessPractice.practice(id: suggestion.practiceId).map {
                    SuggestedPractice(practice: $0, reason: suggestion.reason)
                }
            }
            return mapped.isEmpty ? WellnessFallback.suggestions() : mapped
        } catch {
            return WellnessFallback.suggestions()
        }
    }
}
