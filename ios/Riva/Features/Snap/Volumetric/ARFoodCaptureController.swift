import ARKit
import simd

/// One collected candidate frame from a tap-and-hold capture: the raw
/// camera image, its exact pose/intrinsics/resolution, and (Tier A only)
/// the paired scene-depth map. `FrameSelector` scores these; the manifest
/// builder in `VolumetricCapturePayload` serializes the ones it keeps.
struct CapturedFrame {
    let capturedImage: CVPixelBuffer
    /// `frame.camera.transform` — ARKit world-space camera pose.
    let transform: simd_float4x4
    let intrinsics: simd_float3x3
    let imageResolution: CGSize
    /// `frame.sceneDepth?.depthMap` — populated on Tier A only.
    let depthMap: CVPixelBuffer?
}

/// Owns the `ARSession` behind a tap-and-hold volumetric capture.
///
/// Backs the "3D scan (beta)" flow only: never touched by the shipping
/// single-photo Snap flow. Frames collected during a hold arrive on ARKit's
/// session-delegate thread;
/// `lock` guards the candidate buffer so the main-actor view model can read
/// it back safely once the hold ends.
final class ARFoodCaptureController: NSObject, ARSessionDelegate {

    /// Every Nth tracked frame becomes a candidate. ARKit updates at up to
    /// 60Hz; keeping every frame for a 5s hold would be ~300 full-resolution
    /// pixel buffers — far more than `FrameSelector` needs to pick 6.
    private static let sampleEveryN = 6

    let tier: CaptureCapability
    private let session = ARSession()
    private let lock = NSLock()
    private var frameCounter = 0
    private var isCapturing = false
    private var candidates: [CapturedFrame] = []

    var underlyingSession: ARSession { session }

    init(tier: CaptureCapability = .resolve()) {
        self.tier = tier
        super.init()
        session.delegate = self
    }

    /// Runs the AR session so the camera preview has something to show.
    /// No-op on Tier C (Simulator / unsupported hardware) so this never
    /// touches ARKit where it isn't supported.
    func startSession() {
        guard tier != .tierC, ARWorldTrackingConfiguration.isSupported else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        if tier == .tierA, ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        session.run(configuration)
    }

    func pauseSession() {
        guard tier != .tierC else { return }
        session.pause()
    }

    /// Begins collecting candidates for one tap-and-hold; call
    /// `stopCapture()` when the hold ends.
    func startCapture() {
        guard tier != .tierC else { return }
        lock.lock()
        candidates = []
        frameCounter = 0
        isCapturing = true
        lock.unlock()
    }

    /// Ends collection and returns whatever candidates were gathered.
    @discardableResult
    func stopCapture() -> [CapturedFrame] {
        lock.lock()
        isCapturing = false
        let collected = candidates
        candidates = []
        lock.unlock()
        return collected
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lock.lock()
        defer { lock.unlock() }
        guard isCapturing else { return }
        frameCounter += 1
        guard frameCounter % Self.sampleEveryN == 0 else { return }

        candidates.append(CapturedFrame(
            capturedImage: frame.capturedImage,
            transform: frame.camera.transform,
            intrinsics: frame.camera.intrinsics,
            imageResolution: frame.camera.imageResolution,
            depthMap: tier == .tierA ? frame.sceneDepth?.depthMap : nil
        ))
    }
}
