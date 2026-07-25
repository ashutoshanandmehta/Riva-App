import Foundation

/// Live to-do repository backed by the Riva scan service's `/v1/todos`
/// endpoints. Same transport rules as `APILogRepository`: token from the auth
/// repository, 401 surfaces as `signInRequired`.
struct APITodoRepository: TodoRepository {

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

    func todos() async throws -> [Todo] {
        struct Wire: Decodable {
            let todos: [Todo]
        }
        let wire: Wire = try await decoded("v1/todos", method: "GET", body: nil)
        return wire.todos
    }

    func save(_ draft: TodoDraft) async throws -> Todo {
        struct Body: Encodable {
            let id: String?
            let title: String
            let category: String
            let repeatRule: String
            let remindHour: Int
            let remindMinute: Int
            let dueDate: String?
        }
        let calendar = Calendar.current
        let once = draft.repeatRule == .once
        return try await decoded("v1/todos", method: "POST", body: encode(Body(
            id: draft.id,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category.rawValue,
            repeatRule: draft.repeatRule.rawValue,
            remindHour: calendar.component(.hour, from: draft.time),
            remindMinute: calendar.component(.minute, from: draft.time),
            // A daily to-do carries no date; the server rejects one anyway.
            dueDate: once ? AccountDates.dayString(draft.day) : nil
        )))
    }

    func setDone(id: String, done: Bool) async throws -> Todo {
        struct Body: Encodable {
            let done: Bool
        }
        return try await decoded(
            "v1/todos/\(id)/done", method: "POST", body: encode(Body(done: done))
        )
    }

    /// Idempotent: a to-do that is already gone counts as deleted, so a 404
    /// resolves rather than throwing and bouncing the row back onto the card.
    func delete(id: String) async throws {
        _ = try await data(
            for: "v1/todos/\(id)", method: "DELETE", body: nil, treatingNotFoundAsSuccess: true
        )
    }

    // MARK: Transport

    private func encode(_ body: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
    }

    private func decoded<Response: Decodable>(
        _ path: String, method: String, body: Data?
    ) async throws -> Response {
        let payload = try await data(for: path, method: method, body: body)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: payload)
    }

    private func data(
        for path: String,
        method: String,
        body: Data?,
        treatingNotFoundAsSuccess: Bool = false
    ) async throws -> Data {
        guard let token = try await auth.validAccessToken() else {
            throw ScanServiceError.signInRequired
        }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let payload: Data
        let response: URLResponse
        do {
            (payload, response) = try await urlSession.data(for: request)
        } catch {
            throw ScanServiceError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw ScanServiceError.unreachable
        }
        switch http.statusCode {
        case 200..<300:
            return payload
        case 401:
            throw ScanServiceError.signInRequired
        case 404 where treatingNotFoundAsSuccess:
            return Data()
        default:
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: payload))?.detail
            throw ScanServiceError.service(detail ?? "Could not save the to-do. Try again.")
        }
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }
}
