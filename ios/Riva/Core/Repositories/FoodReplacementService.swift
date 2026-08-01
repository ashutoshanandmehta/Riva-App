import Foundation

/// Replacements for a mis-detected scan item, so a wrong read can be corrected
/// in place instead of costing another photo scan.
///
/// The server prices every candidate against USDA, and falls back to a Claude
/// recipe — decomposed into ingredients USDA *does* know — for dishes it has no
/// entry for.
protocol FoodReplacementService: Sendable {
    /// Likely replacements for the item, with no user text yet.
    func suggestions(for context: FoodReplacementContext) async throws -> [FoodSuggestion]

    /// The food the user typed, priced. Returns at most one result, which the
    /// editor applies straight away.
    func search(_ query: String, in context: FoodReplacementContext) async throws -> [FoodSuggestion]
}

/// Live service backed by the scan service's food-search endpoint. Same
/// transport rules as `APILogRepository`: token from the auth repository,
/// 401 surfaces as `signInRequired`, everything else fails soft into a message
/// the editor can show without disturbing the rest of the result card.
struct APIFoodReplacementService: FoodReplacementService {

    private let baseURL: URL
    private let auth: any AuthRepository
    private let urlSession: URLSession

    init(auth: any AuthRepository, baseURL: URL = BackendEnvironment.scanServiceURL) {
        self.auth = auth
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        // Generous: the free tier host sleeps and takes up to a minute to wake.
        config.timeoutIntervalForRequest = 120
        urlSession = URLSession(configuration: config)
    }

    func suggestions(for context: FoodReplacementContext) async throws -> [FoodSuggestion] {
        try await post(search: "", context)
    }

    func search(_ query: String, in context: FoodReplacementContext) async throws -> [FoodSuggestion] {
        try await post(search: query, context)
    }

    // MARK: Transport

    private struct Body: Encodable {
        let originalItem: String
        let search: String
        let plateContext: String
        let otherItems: [String]
        /// The portion already measured in that spot on the plate. A searched
        /// food keeps it, so only the food changes.
        let originalGrams: Double
        let originalPortionDesc: String
    }

    private func post(
        search: String,
        _ context: FoodReplacementContext
    ) async throws -> [FoodSuggestion] {
        guard let token = try await auth.validAccessToken() else {
            throw ScanServiceError.signInRequired
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        var request = URLRequest(url: baseURL.appending(path: "v1/food-search"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Body(
            originalItem: context.originalItem,
            search: search,
            plateContext: context.plateContext ?? "",
            otherItems: context.otherItems,
            originalGrams: context.originalGrams,
            originalPortionDesc: context.originalPortionDesc
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ScanServiceError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw ScanServiceError.unreachable
        }
        switch http.statusCode {
        case 200..<300:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode([FoodSuggestion].self, from: data)
        case 401:
            throw ScanServiceError.signInRequired
        case 404, 405:
            // The route is not deployed yet — the static mount answers instead,
            // and its "Method Not Allowed" is not something to show a user.
            throw ScanServiceError.service("Food search is not available yet.")
        default:
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
            throw ScanServiceError.service(detail ?? "Could not look up other foods. Try again.")
        }
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }
}

/// Fixture service for previews and the simulator walkthrough.
struct MockFoodReplacementService: FoodReplacementService {

    func suggestions(for context: FoodReplacementContext) async throws -> [FoodSuggestion] {
        try? await Task.sleep(for: .milliseconds(500))
        return Self.noodles
    }

    /// One result, like the live service: the editor applies it directly.
    func search(_ query: String, in context: FoodReplacementContext) async throws -> [FoodSuggestion] {
        try? await Task.sleep(for: .milliseconds(500))
        guard !query.isEmpty else { return Self.noodles }
        let hit = Self.noodles.first { $0.name.localizedCaseInsensitiveContains(query) }
        return [hit ?? FoodSuggestion(
            name: query,
            portionDesc: context.originalPortionDesc.isEmpty ? "1 serving" : context.originalPortionDesc,
            portionGrams: context.originalGrams > 0 ? context.originalGrams : 100,
            calories: 288,
            proteinGrams: 5,
            carbGrams: 38,
            fiberGrams: 1,
            fatG: 12.5,
            sugarG: 0.2,
            sodiumMg: 776,
            matched: false
        )]
    }

    static let noodles = [
        FoodSuggestion(
            name: "noodles",
            portionDesc: "1 serving",
            portionGrams: 70,
            calories: 340,
            proteinGrams: 8,
            carbGrams: 62,
            fiberGrams: 3,
            fatG: 5.4,
            sugarG: 1.2,
            sodiumMg: 620,
            matched: true
        ),
        FoodSuggestion(
            name: "instant noodles",
            portionDesc: "1 cake",
            portionGrams: 70,
            calories: 385,
            proteinGrams: 8,
            carbGrams: 54,
            fiberGrams: 2,
            fatG: 15.2,
            sugarG: 0.9,
            sodiumMg: 1200,
            matched: true
        ),
        FoodSuggestion(
            name: "ramen",
            portionDesc: "1 bowl",
            portionGrams: 250,
            calories: 436,
            proteinGrams: 19,
            carbGrams: 60,
            fiberGrams: 4,
            fatG: 13.0,
            sugarG: 2.1,
            sodiumMg: 1820,
            matched: false
        ),
        FoodSuggestion(
            name: "pasta",
            portionDesc: "1 cup cooked",
            portionGrams: 140,
            calories: 220,
            proteinGrams: 8,
            carbGrams: 43,
            fiberGrams: 3,
            fatG: 1.3,
            sugarG: 0.8,
            sodiumMg: 6,
            matched: true
        ),
    ]
}
