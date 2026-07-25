import ARKit

/// Runtime capture tier for the "3D scan (beta)" ARKit volumetric food
/// capture flow. Resolved once per capture session; cheap to call.
///
/// - `.tierA`: LiDAR present — dense per-frame scene depth is available.
/// - `.tierB`: ARKit world tracking works (metric camera pose) but no dense
///   depth (no LiDAR on this device).
/// - `.tierC`: ARKit is unavailable altogether (Simulator, or hardware too
///   old for world tracking) — the capture flow must degrade to a clear
///   message and never touch `ARSession`.
enum CaptureCapability: Equatable {
    case tierA
    case tierB
    case tierC

    /// The single-letter tier code the backend manifest expects
    /// (`app.volumetric.payload.CaptureSet.tier`).
    var manifestCode: String {
        switch self {
        case .tierA: "A"
        case .tierB: "B"
        case .tierC: "C"
        }
    }

    static func resolve() -> CaptureCapability {
        guard ARWorldTrackingConfiguration.isSupported else { return .tierC }
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else { return .tierB }
        return .tierA
    }

    /// Pre-entry gate for the Snap radial menu: whether the "3D scan (beta)"
    /// action should even be offered on this device, before the capture
    /// screen (and its own `resolve()` check) is ever reached. The
    /// Simulator has no ARKit but is still treated as supported so the flow
    /// stays reviewable there, matching `ARFoodCaptureView`'s own
    /// simulator handling.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return resolve() != .tierC
        #endif
    }
}
