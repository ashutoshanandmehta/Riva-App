import Accelerate
import CoreVideo
import simd

/// Picks the best subset of a tap-and-hold's captured frames to upload:
/// sharp, and spread out in camera pose rather than clustered from holding
/// the phone still. Pure CPU (Accelerate for the sharpness metric, simd for
/// pose distance) — no ML, and nothing that needs Tier A depth.
enum FrameSelector {

    /// Aim to keep this many frames; never return fewer than
    /// `minimumFrames` unless the raw candidate pool itself is smaller.
    static let targetFrames = 6
    static let minimumFrames = 3

    /// Frames scoring below this are treated as motion-blurred. Empirical:
    /// a steady ARKit frame in normal indoor light scores in the low
    /// hundreds; anything under ~25 is a mid-move or out-of-focus frame.
    private static let sharpnessFloor: Double = 25

    struct Scored {
        let frame: CapturedFrame
        let sharpness: Double
    }

    /// Scores every candidate for sharpness, discards the blurriest, then
    /// greedily picks up to `targetFrames` by farthest-point sampling over
    /// camera pose so the selection covers distinct viewpoints instead of
    /// near-duplicates from holding the phone still.
    static func select(from candidates: [CapturedFrame]) -> [Scored] {
        guard !candidates.isEmpty else { return [] }

        let scored = candidates.map { Scored(frame: $0, sharpness: sharpness(of: $0.capturedImage)) }
        let sharpEnough = scored.filter { $0.sharpness >= sharpnessFloor }
        // A genuinely dim room can push everything below the floor; fall
        // back to ranking by sharpness alone rather than failing the
        // capture outright.
        let pool = sharpEnough.count >= minimumFrames
            ? sharpEnough
            : scored.sorted { $0.sharpness > $1.sharpness }

        return farthestPointSample(pool, count: min(targetFrames, pool.count))
    }

    // MARK: Sharpness (Laplacian variance)

    /// Laplacian-variance sharpness over the frame's luma plane — no color
    /// conversion needed since ARKit's `capturedImage` is always biplanar
    /// YCbCr with luma in plane 0. Subsampled on a stride grid: this only
    /// needs to rank a few dozen candidates against each other, not measure
    /// an absolute blur unit.
    static func sharpness(of pixelBuffer: CVPixelBuffer) -> Double {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0 else { return 0 }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        let stride = 4
        guard width > stride * 2, height > stride * 2 else { return 0 }

        var responses: [Float] = []
        responses.reserveCapacity((width / stride) * (height / stride))

        var y = stride
        while y < height - stride {
            var x = stride
            while x < width - stride {
                let center = Int(luma[y * rowBytes + x])
                let up = Int(luma[(y - stride) * rowBytes + x])
                let down = Int(luma[(y + stride) * rowBytes + x])
                let left = Int(luma[y * rowBytes + (x - stride)])
                let right = Int(luma[y * rowBytes + (x + stride)])
                responses.append(Float(up + down + left + right - 4 * center))
                x += stride
            }
            y += stride
        }
        guard !responses.isEmpty else { return 0 }

        var mean: Float = 0
        vDSP_meanv(responses, 1, &mean, vDSP_Length(responses.count))
        var meanOfSquares: Float = 0
        vDSP_measqv(responses, 1, &meanOfSquares, vDSP_Length(responses.count))
        return Double(meanOfSquares - mean * mean) // variance = E[x^2] - E[x]^2
    }

    // MARK: Pose diversity (greedy farthest-point sampling)

    /// Always keeps the sharpest frame first, then repeatedly adds whichever
    /// remaining candidate is farthest (in pose space) from everything
    /// already picked, so the final set spans distinct viewpoints instead
    /// of near-duplicates from a nearly-still hold.
    private static func farthestPointSample(_ pool: [Scored], count: Int) -> [Scored] {
        guard count > 0, !pool.isEmpty else { return [] }
        var remaining = pool
        var picked: [Scored] = []

        let seedIndex = remaining.indices.max { remaining[$0].sharpness < remaining[$1].sharpness }!
        picked.append(remaining.remove(at: seedIndex))

        while picked.count < count, !remaining.isEmpty {
            var bestIndex = remaining.startIndex
            var bestDistance = -Double.infinity
            for index in remaining.indices {
                let distance = picked
                    .map { poseDistance($0.frame.transform, remaining[index].frame.transform) }
                    .min() ?? .infinity
                if distance > bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            picked.append(remaining.remove(at: bestIndex))
        }
        return picked
    }

    /// Translation distance (meters) plus a scaled angular distance between
    /// forward vectors (ARKit's camera looks down -Z in its own space), so a
    /// pure pivot-in-place still counts as a different viewpoint.
    private static func poseDistance(_ a: simd_float4x4, _ b: simd_float4x4) -> Double {
        let positionA = SIMD3<Float>(a.columns.3.x, a.columns.3.y, a.columns.3.z)
        let positionB = SIMD3<Float>(b.columns.3.x, b.columns.3.y, b.columns.3.z)
        let translationDistance = simd_distance(positionA, positionB)

        let forwardA = -SIMD3<Float>(a.columns.2.x, a.columns.2.y, a.columns.2.z)
        let forwardB = -SIMD3<Float>(b.columns.2.x, b.columns.2.y, b.columns.2.z)
        let cosAngle = simd_clamp(simd_dot(simd_normalize(forwardA), simd_normalize(forwardB)), -1, 1)

        // Meters and radians aren't natively comparable; this weighting
        // keeps a ~10cm step and a ~30deg turn roughly equally "diverse"
        // for a food capture orbiting at arm's length.
        return Double(translationDistance) + Double(acos(cosAngle)) * 0.3
    }
}
