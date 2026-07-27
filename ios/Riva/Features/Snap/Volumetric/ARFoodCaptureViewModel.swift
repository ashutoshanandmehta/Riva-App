import ARKit
import CoreImage
import Foundation
import Observation
import UIKit

/// Orchestrates the "3D scan (beta)" tap-and-hold volumetric capture: runs
/// the AR session, collects frames while the user holds, selects the best
/// subset, shows a review step, calls the volumetric scan endpoint, then
/// (on explicit user confirmation) logs the result through the same
/// authenticated accept path the single-photo scanner uses.
///
/// Flow: `idle` → (hold) `capturing` → (release) `review` → (Proceed)
/// `processing` → `result` → (Accept) `saving` → `saved`. Retake returns
/// `review`/`error` to `idle`.
@MainActor
@Observable
final class ARFoodCaptureViewModel {

    enum Stage: Equatable {
        case idle
        case capturing(progress: Double)
        case review
        case processing
        case result(ScanResult)
        case saving(ScanResult)
        case saved(DayTotals)
        case error(String)
    }

    /// Staged messaging for the ~20-30s processing call — there is no
    /// incremental server progress to report, so this advances on a timer
    /// while the request is in flight, purely so the wait doesn't read as a
    /// bare, uninformative spinner.
    enum ProcessingStep: String, CaseIterable {
        case uploading = "Uploading your capture…"
        case identifying = "Identifying what's on the plate…"
        case measuring = "Measuring portion size…"

        var progress: Double {
            switch self {
            case .uploading: 0.15
            case .identifying: 0.55
            case .measuring: 0.9
            }
        }
    }

    /// A hold shorter than this is treated as an accidental tap — not
    /// enough frames for multi-view coverage.
    private let minHoldSeconds: Double = 3
    /// A hold longer than this auto-completes the capture even if still
    /// held, matching the "3-5s hold" target.
    private let maxHoldSeconds: Double = 5
    /// How long each processing step is shown before advancing to the next,
    /// tuned to the ~20-30s the volumetric pipeline typically takes.
    private let processingStepSeconds: Double = 7

    private(set) var stage: Stage = .idle

    /// The day's running totals returned by an accepted scan, so closing the
    /// flow can hand them to the dashboards for an instant update instead of
    /// leaving them stale until the background refetch lands. Nil until
    /// something is logged.
    var loggedTotals: DayTotals? {
        guard case .saved(let totals) = stage else { return nil }
        return totals
    }

    private(set) var processingStep: ProcessingStep = .uploading
    /// Transient problem shown near the Accept action on the result screen
    /// (a failed log, not a failed scan — the scan itself is `stage`).
    private(set) var confirmError: String?
    let tier: CaptureCapability

    /// One free-text field (unstructured): the user jots whatever they know
    /// about the dish — name, rough weight, hidden oil/butter — in their own
    /// words. Passed to the scan as a loose hint; entirely optional.
    var details: String = ""

    /// Displayable frames of the just-captured arc, shown as a looping preview
    /// on the review screen. Empty in the Simulator (no camera).
    private(set) var previewImages: [UIImage] = []

    private let controller: ARFoodCaptureController
    private let repository: any VolumetricScanRepository
    /// Persists an accepted scan through the same server-authoritative path
    /// `APIScanRepository.accept` exposes to the photo scanner — this flow
    /// never talks to a volumetric-specific logging endpoint.
    private let accept: @Sendable (ScanResult) async throws -> DayTotals
    private var holdStartedAt: Date?
    private var progressTask: Task<Void, Never>?
    private var pendingFrames: [FrameSelector.Scored] = []
    private var pendingCaptureMs = 0

    private static let ciContext = CIContext()

    init(
        repository: any VolumetricScanRepository,
        accept: @escaping @Sendable (ScanResult) async throws -> DayTotals,
        controller: ARFoodCaptureController = ARFoodCaptureController()
    ) {
        self.repository = repository
        self.accept = accept
        self.controller = controller
        self.tier = controller.tier
    }

    var arSession: ARSession { controller.underlyingSession }

    func onAppear() {
        controller.startSession()
        #if targetEnvironment(simulator)
        // Sim-only: jump straight to the review screen so its UI is reviewable
        // without a device (the Simulator can't capture).
        if ProcessInfo.processInfo.arguments.contains("-riva.volumetric.review") {
            simulateReview()
        }
        #endif
    }

    func onDisappear() {
        progressTask?.cancel()
        progressTask = nil
        controller.pauseSession()
    }

    /// Call when the hold gesture presses down.
    func beginHold() {
        guard tier != .tierC else { return }
        switch stage {
        case .idle, .error: break
        case .capturing, .review, .processing, .result, .saving, .saved: return
        }

        controller.startCapture()
        // Feedback: a firm tap confirms the hold registered and capture began.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let startedAt = Date()
        holdStartedAt = startedAt
        stage = .capturing(progress: 0)

        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                if elapsed >= self.maxHoldSeconds {
                    self.endHold()
                    return
                }
                self.stage = .capturing(progress: elapsed / self.maxHoldSeconds)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Call when the hold gesture releases (or fires automatically at
    /// `maxHoldSeconds`). Selects frames and moves to the review step.
    func endHold() {
        guard case .capturing = stage, let startedAt = holdStartedAt else { return }
        progressTask?.cancel()
        progressTask = nil
        holdStartedAt = nil

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let rawFrames = controller.stopCapture()

        guard elapsedMs >= Int(minHoldSeconds * 1000) else {
            stage = .error("Hold for at least \(Int(minHoldSeconds)) seconds so there's enough to work with.")
            return
        }
        let selected = FrameSelector.select(from: rawFrames)
        guard selected.count >= FrameSelector.minimumFrames else {
            stage = .error("Not enough sharp frames were captured. Try again with more light or a steadier hold.")
            return
        }
        pendingFrames = selected
        pendingCaptureMs = elapsedMs
        previewImages = selected.compactMap { Self.image(from: $0.frame.capturedImage) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        stage = .review
    }

    /// From the review step: upload the captured set with the free-text details.
    func proceed() {
        guard !pendingFrames.isEmpty else { return }
        Task { await process(frames: pendingFrames, captureMs: pendingCaptureMs) }
    }

    /// Back to the camera to capture again (keeps whatever details were typed).
    func retake() {
        pendingFrames = []
        previewImages = []
        confirmError = nil
        stage = .idle
    }

    #if targetEnvironment(simulator)
    /// The Simulator has no ARKit, so a tap on the shutter jumps to the review
    /// step with an empty preview — enough to walk the two-screen flow's UI.
    func simulateReview() {
        previewImages = []
        stage = .review
    }
    #endif

    /// From the result step: the explicit, required confirmation tap before
    /// a volumetric scan is ever logged. No-ops for `not_food` results —
    /// `/v1/log` only accepts `food`/`beverage`/`water`, and `ScanResultCard`
    /// already withholds the Accept action in that case.
    func confirmAndLog() async {
        guard case .result(let scan) = stage, scan.scanType != .notFood else { return }
        stage = .saving(scan)
        confirmError = nil
        do {
            stage = .saved(try await accept(scan))
        } catch {
            stage = .result(scan)
            confirmError = error.localizedDescription
        }
    }

    private func process(frames: [FrameSelector.Scored], captureMs: Int) async {
        stage = .processing
        processingStep = .uploading
        let stepTask = advanceProcessingStepsTask()
        defer { stepTask.cancel() }

        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = text.isEmpty ? nil : text
        do {
            let request = try VolumetricCapturePayload.build(
                tier: tier,
                captureMs: captureMs,
                mode: "food",
                hint: nil,
                frames: frames
            )
            stage = .result(try await repository.scan(
                request,
                label: nil,
                gramsTruth: nil,
                hint: notes
            ))
        } catch {
            stage = .error(error.localizedDescription)
        }
    }

    /// Cycles `processingStep` forward on a timer for as long as `process(...)`
    /// is awaiting the network call; cancelled once it returns (success or
    /// failure) so it never outlives the request.
    private func advanceProcessingStepsTask() -> Task<Void, Never> {
        Task { [weak self] in
            for step in ProcessingStep.allCases.dropFirst() {
                guard let seconds = self?.processingStepSeconds else { return }
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.processingStep = step
            }
        }
    }

    /// ARKit's `capturedImage` is landscape sensor YCbCr; rotate to portrait
    /// for display in the review preview.
    private static func image(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
