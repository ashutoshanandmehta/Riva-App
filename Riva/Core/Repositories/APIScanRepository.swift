import Foundation

/// Live scan repository backed by the Riva scan service.
///
/// Auth is delegated to the injected `AuthRepository`: every call fetches a
/// fresh access token, and a 401 surfaces as `signInRequired` so the UI can
/// flip to the sign-in step without special-casing HTTP anywhere else.
struct APIScanRepository: ScanRepository {

    private let baseURL: URL
    private let auth: any AuthRepository
    private let urlSession: URLSession

    init(auth: any AuthRepository, baseURL: URL = BackendEnvironment.scanServiceURL) {
        self.auth = auth
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        // Generous: the free tier host sleeps and takes up to a minute to
        // wake, and a scan itself runs several seconds.
        config.timeoutIntervalForRequest = 120
        urlSession = URLSession(configuration: config)
    }

    func scan(imageData: Data, mode: ScanMode) async throws -> ScanResult {
        guard let token = try await auth.validAccessToken() else {
            throw ScanServiceError.signInRequired
        }

        let boundary = "riva-scan-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"mode\"\r\n\r\n\(mode.rawValue)\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"image\"; filename=\"scan.jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: baseURL.appending(path: "v1/scan"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        return try await send(request)
    }

    func accept(_ scan: ScanResult) async throws -> DayTotals {
        guard let token = try await auth.validAccessToken() else {
            throw ScanServiceError.signInRequired
        }

        let delta = scan.nutritionDayDelta
        let entry = LogEntry(
            scanType: scan.scanType.rawValue,
            items: scan.items.map(LoggedItem.init),
            calories: delta.calories,
            proteinGrams: delta.proteinGrams,
            carbGrams: delta.carbGrams,
            fiberGrams: delta.fiberGrams,
            waterOunces: delta.waterOunces,
            model: scan.model,
            promptVersion: scan.promptVersion
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        var request = URLRequest(url: baseURL.appending(path: "v1/log"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(entry)

        return try await send(request)
    }

    // MARK: Request bodies

    private struct LoggedItem: Encodable {
        let name: String
        let portionGrams: Double
        let calories: Int
        let proteinGrams: Int
        let matched: Bool
        let fdcId: Int?

        init(_ item: ScanItem) {
            name = item.name
            portionGrams = item.portionGrams
            calories = item.calories
            proteinGrams = item.proteinGrams
            matched = item.matched
            fdcId = item.fdcId
        }
    }

    private struct LogEntry: Encodable {
        let scanType: String
        let items: [LoggedItem]
        let calories: Int
        let proteinGrams: Int
        let carbGrams: Int
        let fiberGrams: Int
        let waterOunces: Int
        let model: String?
        let promptVersion: String?
    }

    // MARK: Transport

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
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
            throw ScanServiceError.service(detail ?? "The scan service had a problem. Try again.")
        }
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
