import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import simd

/// Builds the multipart `/v1/scan/volumetric` request from the frames
/// `FrameSelector` chose. The manifest and multipart layout MUST match
/// `app/volumetric/payload.py` exactly:
///
///     { "tier": "B", "capture_ms": 3200, "hint": null, "mode": "food",
///       "frames": [ { "file": "frame_0000.jpg", "pose": [16 floats]|null,
///         "intrinsics": {"fx":..,"fy":..,"cx":..,"cy":..}|null,
///         "width": 1440, "height": 1920, "depth_file": "depth_0000.bin"|null,
///         "sharpness": 137.4 } ] }
///
/// One `manifest` form field carries that JSON; every frame/depth it
/// references is a separate file part. The backend matches parts to the
/// manifest by **upload filename** (`file`/`depth_file`), not by form field
/// name, so every part here shares the generic field name `"frames"`.
///
/// `appendingEvalFields(...)` separately adds three OPTIONAL plain-text
/// form fields — `label`, `grams_truth`, `hint` — the DEBUG eval-capture
/// flow uses to bank a ground-truth dataset on the backend. They are not
/// part of the manifest JSON; each is its own top-level multipart part,
/// included only when the user actually provided it.
enum VolumetricCapturePayload {

    struct Request: Sendable {
        let httpBody: Data
        let contentType: String
        /// The multipart boundary token used in `contentType`, kept around
        /// so `appendingEvalFields` can reopen the body's closing boundary
        /// without re-parsing it out of the content-type string.
        let boundary: String
    }

    enum PayloadError: LocalizedError {
        case emptyFrames
        case imageEncodingFailed(file: String)

        var errorDescription: String? {
            switch self {
            case .emptyFrames:
                "No frames were selected for upload."
            case .imageEncodingFailed(let file):
                "Could not encode \(file) for upload."
            }
        }
    }

    /// JPEG quality for uploaded frames. Uploaded at the camera's exact
    /// `imageResolution` — no downscale — because `width`/`height` and the
    /// intrinsics in the manifest describe that resolution; resizing here
    /// without rescaling intrinsics would desync them.
    private static let jpegQuality: CGFloat = 0.8
    private static let ciContext = CIContext()

    static func build(
        tier: CaptureCapability,
        captureMs: Int,
        mode: String,
        hint: String?,
        frames: [FrameSelector.Scored]
    ) throws -> Request {
        guard !frames.isEmpty else { throw PayloadError.emptyFrames }

        var frameManifests: [FrameManifest] = []
        var fileParts: [(filename: String, contentType: String, data: Data)] = []

        for (index, scored) in frames.enumerated() {
            let frame = scored.frame
            let fileName = String(format: "frame_%04d.jpg", index)
            guard let jpeg = jpegData(from: frame.capturedImage) else {
                throw PayloadError.imageEncodingFailed(file: fileName)
            }
            fileParts.append((fileName, "image/jpeg", jpeg))

            var depthFileName: String?
            if let depthMap = frame.depthMap {
                let depthName = String(format: "depth_%04d.bin", index)
                fileParts.append((depthName, "application/octet-stream", rawDepthBytes(from: depthMap)))
                depthFileName = depthName
            }

            frameManifests.append(FrameManifest(
                file: fileName,
                pose: rowMajorPose(from: frame.transform),
                intrinsics: manifestIntrinsics(from: frame.intrinsics),
                width: Int(frame.imageResolution.width),
                height: Int(frame.imageResolution.height),
                depthFile: depthFileName,
                sharpness: scored.sharpness
            ))
        }

        let manifest = VolumetricManifest(
            tier: tier.manifestCode,
            captureMs: captureMs,
            hint: hint,
            mode: mode,
            frames: frameManifests
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let manifestJSON = String(data: try encoder.encode(manifest), encoding: .utf8) ?? "{}"

        let boundary = "riva-volumetric-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"manifest\"\r\n\r\n")
        body.appendUTF8(manifestJSON)
        body.appendUTF8("\r\n")
        for part in fileParts {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"frames\"; filename=\"\(part.filename)\"\r\n")
            body.appendUTF8("Content-Type: \(part.contentType)\r\n\r\n")
            body.append(part.data)
            body.appendUTF8("\r\n")
        }
        body.appendUTF8("--\(boundary)--\r\n")

        return Request(
            httpBody: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            boundary: boundary
        )
    }

    /// Appends the optional eval ground-truth fields — `label`,
    /// `grams_truth`, `hint` — onto an already-built request, so the DEBUG
    /// eval-capture flow can bank them for a ground-truth dataset without
    /// touching the manifest or frame parts `build(...)` already
    /// serialized. Each field is added only when non-nil and non-blank
    /// (trimmed); if none are provided, `request` is returned unchanged.
    static func appendingEvalFields(
        label: String?,
        gramsTruth: String?,
        hint: String?,
        to request: Request
    ) -> Request {
        let fields: [(name: String, value: String)] = [
            ("label", label),
            ("grams_truth", gramsTruth),
            ("hint", hint),
        ].compactMap { name, value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return (name, trimmed)
        }
        guard !fields.isEmpty else { return request }

        let closingBoundary = Data("--\(request.boundary)--\r\n".utf8)
        guard request.httpBody.suffix(closingBoundary.count) == closingBoundary else {
            // Defensive: `build(...)` always ends the body this way. If that
            // ever changes, fail soft by leaving the request untouched
            // rather than emit a corrupt multipart body.
            return request
        }

        var body = request.httpBody
        body.removeLast(closingBoundary.count)
        for (name, value) in fields {
            body.appendUTF8("--\(request.boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8(value)
            body.appendUTF8("\r\n")
        }
        body.appendUTF8("--\(request.boundary)--\r\n")

        return Request(httpBody: body, contentType: request.contentType, boundary: request.boundary)
    }

    // MARK: simd -> manifest

    /// Row-major 4x4 ARKit world transform. simd stores `simd_float4x4`
    /// column-major (`transform.columns` is a 4-tuple of `SIMD4<Float>`), so
    /// this walks rows on the outside to emit the row-major order the
    /// backend expects.
    private static func rowMajorPose(from transform: simd_float4x4) -> [Float] {
        let columns = [transform.columns.0, transform.columns.1, transform.columns.2, transform.columns.3]
        var values: [Float] = []
        values.reserveCapacity(16)
        for row in 0..<4 {
            for column in columns {
                values.append(column[row])
            }
        }
        return values
    }

    private static func manifestIntrinsics(from intrinsics: simd_float3x3) -> IntrinsicsManifest {
        IntrinsicsManifest(
            fx: intrinsics.columns.0[0],
            fy: intrinsics.columns.1[1],
            cx: intrinsics.columns.2[0],
            cy: intrinsics.columns.2[1]
        )
    }

    // MARK: Image / depth encoding

    private static func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality]
        )
    }

    /// Serializes a Tier A scene-depth buffer (`kCVPixelFormatType_DepthFloat32`,
    /// meters) to a tightly packed, row-major, little-endian Float32 blob —
    /// device memory is already little-endian, so this is a straight byte
    /// copy per row with any `CVPixelBuffer` row padding stripped.
    ///
    /// Width/height: the depth map's OWN dimensions (typically smaller than
    /// the color frame's `imageResolution` — e.g. ~256x192 for LiDAR scene
    /// depth vs. 1920x1440 color), NOT the manifest's per-frame `width`/
    /// `height`. The manifest carries no separate depth-dimensions field
    /// yet, and the backend does not decode `depth_file` bytes at all as of
    /// the B1 pipeline (`app/volumetric/pipeline.py` accepts poses/depth in
    /// the payload but ignores them) — this is forward-looking plumbing
    /// only; a later milestone must add those fields before depth bytes are
    /// actually read.
    private static func rawDepthBytes(from depthMap: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return Data() }

        let tightRowBytes = width * MemoryLayout<Float32>.size
        var packed = Data(capacity: tightRowBytes * height)
        for row in 0..<height {
            packed.append(Data(bytes: base.advanced(by: row * rowBytes), count: tightRowBytes))
        }
        return packed
    }
}

// MARK: - Manifest wire types (snake_case via `.convertToSnakeCase`)

private struct VolumetricManifest: Encodable {
    let tier: String
    let captureMs: Int
    let hint: String?
    let mode: String
    let frames: [FrameManifest]
}

private struct FrameManifest: Encodable {
    let file: String
    let pose: [Float]?
    let intrinsics: IntrinsicsManifest?
    let width: Int
    let height: Int
    let depthFile: String?
    let sharpness: Double?
}

private struct IntrinsicsManifest: Encodable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
