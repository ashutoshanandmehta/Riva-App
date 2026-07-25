import Foundation

/// The "3D scan (beta)" ARKit volumetric capture flow's scan endpoint: a
/// multi-frame manifest in, the same structured result the single-photo
/// scanner returns. Additive to `ScanRepository` — the shipping single-photo
/// Snap flow never touches this; persisting an accepted result reuses
/// `ScanRepository.accept` instead of a volumetric-specific log endpoint.
///
/// `label`/`gramsTruth`/`hint` are optional eval-dataset ground-truth
/// fields (dish name, kitchen-scale weight in grams, free-text hint) the
/// backend can bank alongside the capture for offline scoring. The
/// shipping UI always passes `label`/`gramsTruth` as `nil` — only the
/// DEBUG-only eval-capture tooling populates them.
protocol VolumetricScanRepository: Sendable {
    func scan(
        _ payload: VolumetricCapturePayload.Request,
        label: String?,
        gramsTruth: String?,
        hint: String?
    ) async throws -> ScanResult
}

/// Live repository backed by `POST /v1/scan/volumetric`.
///
/// Anonymous and stateless, like the plain `/v1/scan` route this mirrors
/// (`app/volumetric/routes.py`) — no auth token, no sign-in error case.
/// Stays this way even in the shipping app: authentication only enters the
/// flow later, when an accepted result is persisted via `ScanRepository.accept`.
struct APIVolumetricScanRepository: VolumetricScanRepository {

    private let baseURL: URL
    private let urlSession: URLSession

    init(baseURL: URL = BackendEnvironment.scanServiceURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        // Generous: same rationale as `APIScanRepository` — the free-tier
        // host can be asleep, and a multi-frame scan runs longer than one.
        config.timeoutIntervalForRequest = 120
        urlSession = URLSession(configuration: config)
    }

    func scan(
        _ payload: VolumetricCapturePayload.Request,
        label: String?,
        gramsTruth: String?,
        hint: String?
    ) async throws -> ScanResult {
        let payload = VolumetricCapturePayload.appendingEvalFields(
            label: label,
            gramsTruth: gramsTruth,
            hint: hint,
            to: payload
        )
        var request = URLRequest(url: baseURL.appending(path: "v1/scan/volumetric"))
        request.httpMethod = "POST"
        request.setValue(payload.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = payload.httpBody

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
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
            throw ScanServiceError.service(detail ?? "The volumetric scan service had a problem. Try again.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ScanResult.self, from: data)
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }
}

/// Canned scanner for previews and UI work without ARKit or the network.
struct MockVolumetricScanRepository: VolumetricScanRepository {
    func scan(
        _ payload: VolumetricCapturePayload.Request,
        label: String?,
        gramsTruth: String?,
        hint: String?
    ) async throws -> ScanResult {
        try? await Task.sleep(for: .seconds(1))
        return MockScanRepository.sampleMeal
    }
}
