import Foundation

/// Live companion repository backed by the Riva scan service's `/v1/chat`
/// endpoints. Same transport rules as `APITodoRepository`: token from the auth
/// repository, 401 surfaces as `signInRequired`.
///
/// Identity never appears in the request itself — no user id, patient id, or
/// email in the body, path, query, or a custom header. The only identifying
/// material is the `Authorization` bearer token, which the backend verifies and
/// resolves to the subject of every read and write. Adding an identifier to a
/// request here would put health data behind a client-supplied claim; don't.
struct APICompanionRepository: CompanionRepository {

    private let baseURL: URL
    private let auth: any AuthRepository
    private let urlSession: URLSession

    init(auth: any AuthRepository, baseURL: URL = BackendEnvironment.scanServiceURL) {
        self.auth = auth
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        // Generous on two counts: the free tier host sleeps and takes up to a
        // minute to wake, and a tool-calling turn is several model round trips.
        config.timeoutIntervalForRequest = 120
        urlSession = URLSession(configuration: config)
    }

    // MARK: Turn

    func send(query: String, threadId: String?, confirm: String?) async throws -> CompanionReply {
        /// The whole request body. Deliberately these three fields and nothing
        /// else; the backend ignores extras and would never trust an id here.
        struct Body: Encodable {
            let query: String
            let threadId: String?
            let confirm: String?
        }
        let payload = try await data(
            for: "v1/chat",
            method: "POST",
            body: encode(Body(query: query, threadId: threadId, confirm: confirm)),
            // A 404 here can only be the thread id: the route itself exists, and
            // an unowned or deleted thread is the one case the caller can fix by
            // forgetting it.
            onNotFound: .throwing(CompanionError.threadGone)
        )
        let wire: ReplyWire = try decode(payload)
        return CompanionReply(
            threadId: wire.threadId,
            message: wire.message,
            writePreview: wire.pendingWrite,
            didWrite: wire.completedWrite
        )
    }

    // MARK: Transcript

    func transcript(threadId: String) async throws -> [CompanionMessage] {
        let payload = try await data(
            for: "v1/chat/threads/\(threadId)", method: "GET", body: nil, onNotFound: .empty
        )
        // A deleted or stale thread: nothing to replay, not an error.
        guard !payload.isEmpty else { return [] }
        let wire: TranscriptWire = try decode(payload)
        return wire.messages.compactMap { message in
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // A stored turn with no prose is a command result, which this client
            // never produces and has nothing to render.
            guard !text.isEmpty else { return nil }
            // Write previews are deliberately not restored. A fingerprint from an
            // earlier session may already be spent, and offering a Confirm button
            // that silently previews again would read as a failed save.
            return CompanionMessage(role: message.role == "user" ? .user : .bot, text: text)
        }
    }

    // MARK: Wire

    /// Only the three fields the UI acts on. Every other key in a tool result —
    /// and there are many, one shape per tool — is ignored, so a new backend
    /// tool cannot break decoding here.
    private struct ToolCallWire: Decodable {
        struct Data: Decodable {
            let status: String?
            let fingerprint: String?
            let willWrite: String?

            // Explicit, because a custom `init(from:)` suppresses synthesis.
            // The decoder's snake-case strategy still applies, so `willWrite`
            // matches `will_write` on the wire.
            private enum CodingKeys: String, CodingKey {
                case status, fingerprint, willWrite
            }

            /// Each field is read independently and a mismatch is treated as
            /// absent. A tool result is free-form JSON, so a future tool whose
            /// result happens to use one of these keys for something else must
            /// not be able to fail the decode of an otherwise good answer.
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                status = try? container.decodeIfPresent(String.self, forKey: .status)
                fingerprint = try? container.decodeIfPresent(String.self, forKey: .fingerprint)
                willWrite = try? container.decodeIfPresent(String.self, forKey: .willWrite)
            }
        }
        let data: Data
    }

    private struct ReplyWire: Decodable {
        let threadId: String
        let message: String?
        let toolCalls: [ToolCallWire]

        /// The last staged write of the turn, if any. Last rather than first:
        /// the model can preview more than once in a turn, and the newest is the
        /// one the answer is asking about.
        var pendingWrite: CompanionWritePreview? {
            for call in toolCalls.reversed() {
                guard call.data.status == "needs_confirmation",
                      let fingerprint = call.data.fingerprint,
                      let willWrite = call.data.willWrite else { continue }
                return CompanionWritePreview(fingerprint: fingerprint, willWrite: willWrite)
            }
            return nil
        }

        /// Whether the turn actually changed stored data. The two statuses a
        /// write tool reports on completion; every other status — a preview, a
        /// read, an error — leaves the user's data as it was.
        var completedWrite: Bool {
            toolCalls.contains { $0.data.status == "saved" || $0.data.status == "deleted" }
        }
    }

    private struct TranscriptWire: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }
        let messages: [Message]
    }

    // MARK: Transport

    private func encode(_ body: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
    }

    private func decode<Response: Decodable>(_ payload: Data) throws -> Response {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: payload)
    }

    /// What a 404 means on a given route. Both companion routes can 404 for the
    /// same underlying reason — a thread that is not this user's — but one wants
    /// to recover and the other wants to shrug.
    private enum NotFound {
        /// Resolve to no data: nothing to replay.
        case empty
        /// Throw this instead of the generic service error.
        case throwing(Error)
    }

    private func data(
        for path: String,
        method: String,
        body: Data?,
        onNotFound: NotFound = .empty
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
        case 404:
            switch onNotFound {
            case .empty: return Data()
            case .throwing(let error): throw error
            }
        default:
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: payload))?.detail
            throw ScanServiceError.service(detail ?? "The companion couldn't answer. Try again.")
        }
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }
}
