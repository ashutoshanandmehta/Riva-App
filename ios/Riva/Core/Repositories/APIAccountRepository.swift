import Foundation

/// Live account repository backed by the Riva scan service's account
/// endpoints. Same transport rules as `APILogRepository`: token from the
/// auth repository, 401 surfaces as `signInRequired`.
struct APIAccountRepository: AccountRepository {

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

    func me() async throws -> AccountBundle {
        try decode(try await send(path: "v1/me", method: "GET"))
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> AccountProfile {
        struct Response: Decodable {
            let profile: AccountProfile
        }
        let response: Response = try decode(
            try await send(path: "v1/profile", method: "POST", body: try encode(update))
        )
        return response.profile
    }

    func updateGoals(_ update: GoalsUpdate) async throws -> NutritionGoals {
        struct Response: Decodable {
            let nutritionGoals: NutritionGoals
        }
        let response: Response = try decode(
            try await send(path: "v1/goals", method: "POST", body: try encode(update))
        )
        return response.nutritionGoals
    }

    func updatePlan(_ update: PlanUpdate) async throws -> MedicationPlan {
        struct Response: Decodable {
            let plan: MedicationPlan
        }
        let response: Response = try decode(
            try await send(path: "v1/plan", method: "POST", body: try encode(update))
        )
        return response.plan
    }

    func weights() async throws -> [WeightEntry] {
        struct Response: Decodable {
            let entries: [WeightEntry]
        }
        let response: Response = try decode(
            try await send(path: "v1/weights?limit=60", method: "GET")
        )
        return response.entries
    }

    func shots() async throws -> [ShotEntry] {
        struct Response: Decodable {
            let entries: [ShotEntry]
        }
        let response: Response = try decode(
            try await send(path: "v1/shots?limit=60", method: "GET")
        )
        return response.entries
    }

    func sideEffects() async throws -> [SideEffectDayLog] {
        struct Response: Decodable {
            let logs: [SideEffectDayLog]
        }
        let response: Response = try decode(
            try await send(path: "v1/side-effects?days=30", method: "GET")
        )
        return response.logs
    }

    func exportData() async throws -> Data {
        try await send(path: "v1/export", method: "GET")
    }

    func deleteAccount() async throws {
        _ = try await send(path: "v1/account", method: "DELETE")
    }

    // MARK: Transport

    private func encode(_ body: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }

    private func send(path: String, method: String, body: Data? = nil) async throws -> Data {
        guard let token = try await auth.validAccessToken() else {
            throw ScanServiceError.signInRequired
        }
        // Composed with URL(string:relativeTo:) because appending(path:)
        // would percent-escape the "?" in query paths.
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw ScanServiceError.unreachable
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

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
            return data
        case 401:
            throw ScanServiceError.signInRequired
        default:
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
            throw ScanServiceError.service(detail ?? "Could not complete the request. Try again.")
        }
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }
}
