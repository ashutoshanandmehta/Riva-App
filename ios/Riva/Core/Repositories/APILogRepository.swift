import Foundation

/// Live quick-log repository backed by the Riva scan service's logging
/// endpoints. Same transport rules as `APIScanRepository`: token from the
/// auth repository, 401 surfaces as `signInRequired`.
struct APILogRepository: LogRepository {

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

    func logWeight(pounds: Double) async throws -> WeightLogResult {
        struct Body: Encodable {
            let pounds: Double
        }
        return try await post("v1/log/weight", Body(pounds: pounds))
    }

    func logShot(
        medicationName: String,
        doseMg: Double,
        site: InjectionSite,
        comfortRating: Int?
    ) async throws -> ShotLogResult {
        struct Body: Encodable {
            let medicationName: String
            let doseMg: Double
            let injectionSite: String
            let comfortRating: Int?
        }
        return try await post("v1/log/shot", Body(
            medicationName: medicationName,
            doseMg: doseMg,
            injectionSite: site.rawValue,
            comfortRating: comfortRating
        ))
    }

    func logProtein(grams: Int) async throws -> DayTotals {
        struct Item: Encodable {
            let name: String
            let source: String
        }
        struct Body: Encodable {
            let scanType: String
            let items: [Item]
            let calories: Int
            let proteinGrams: Int
            let carbGrams: Int
            let fiberGrams: Int
            let waterOunces: Int
            let model: String
        }
        return try await post("v1/log", Body(
            scanType: "food",
            items: [Item(name: "Protein quick add", source: "manual")],
            calories: 0,
            proteinGrams: grams,
            carbGrams: 0,
            fiberGrams: 0,
            waterOunces: 0,
            model: "manual"
        ))
    }

    func logSideEffects(_ entries: [SideEffectEntry]) async throws -> SideEffectsLogResult {
        struct Body: Encodable {
            let effects: [SideEffectEntry]
        }
        return try await post("v1/log/side-effects", Body(effects: entries))
    }

    func logSleep(optionCode: String) async throws -> CheckinLogResult {
        struct Body: Encodable {
            let questionId: String
            let optionCode: String
        }
        return try await post("v1/log/checkin", Body(questionId: "sleep", optionCode: optionCode))
    }

    // MARK: Transport

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String, _ body: Body
    ) async throws -> Response {
        guard let token = try await auth.validAccessToken() else {
            throw ScanServiceError.signInRequired
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

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
            return try decoder.decode(Response.self, from: data)
        case 401:
            throw ScanServiceError.signInRequired
        default:
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
            throw ScanServiceError.service(detail ?? "Could not save the log. Try again.")
        }
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }
}
