import ARKit
import SceneKit
import SwiftUI
import UIKit

/// **3D scan (beta)** — the ARKit depth/volumetric capture flow, as a
/// two-screen, camera-first experience. Additive: the shipping photo
/// scanner (`SnapScanView`) is untouched; this is reached from the Snap
/// radial menu, gated on `CaptureCapability.isSupported`, and labeled
/// experimental throughout — an explicit confirm tap is always required
/// before a scan is logged.
///
/// Screen 1 (camera): full-bleed live camera with Liquid Glass overlays — an
/// aligned header, a framing reticle, embedded instructions, and a native-style
/// Hold-to-Scan shutter. Screen 2 (review): a looping preview of the capture, a
/// single free-text details bar, and Retake / Proceed. HCI heuristics
/// throughout: visibility of status, recognition over recall, clear affordances
/// and feedback, and a minimalist primary task.
struct ARFoodCaptureView: View {
    /// Hands back the day's totals when the flow logged something, so the
    /// dashboards update with it rather than waiting on a refetch.
    let onClose: (DayTotals?) -> Void

    @State private var model: ARFoodCaptureViewModel
    @State private var previewIndex = 0

    init(
        volumetricScanRepository: any VolumetricScanRepository,
        accept: @escaping @Sendable (ScanResult) async throws -> DayTotals,
        onClose: @escaping (DayTotals?) -> Void
    ) {
        self.onClose = onClose
        _model = State(initialValue: ARFoodCaptureViewModel(repository: volumetricScanRepository, accept: accept))
    }

    /// Leaves the flow, carrying the day's totals when a scan was logged.
    private func close() {
        onClose(model.loggedTotals)
    }

    var body: some View {
        ZStack {
            if !isCaptureSupported {
                unsupportedScreen
            } else {
                switch model.stage {
                case .idle, .capturing:
                    cameraScreen
                case .review:
                    reviewScreen
                case .processing:
                    processingScreen
                case .result(let scan):
                    resultScreen(scan)
                case .saving(let scan):
                    savingScreen(scan)
                case .saved(let totals):
                    savedScreen(totals)
                case .error(let message):
                    errorScreen(message)
                }
            }
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .onChange(of: model.stage) { _, stage in
            switch stage {
            case .result, .saved: UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .error: UINotificationFeedbackGenerator().notificationOccurred(.warning)
            default: break
            }
        }
    }

    /// The Simulator has no ARKit, but we still render the full flow there (the
    /// camera area falls back to a placeholder) so the UI is reviewable. A
    /// genuinely unsupported physical device (never a modern iPhone) keeps the
    /// notice.
    private var isCaptureSupported: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return model.tier != .tierC
        #endif
    }

    private var isCapturing: Bool {
        if case .capturing = model.stage { return true }
        return false
    }

    // MARK: - Screen 1: Camera

    private var cameraScreen: some View {
        ZStack {
            cameraLayer
                .ignoresSafeArea()

            reticle

            VStack(spacing: 0) {
                topBar(onBack: close, tint: .white)
                Spacer()
                captureCluster
            }
            .padding(.horizontal, TPCSpacing.screenMargin)
            .padding(.top, TPCSpacing.sm)
            .padding(.bottom, TPCSpacing.xl)
        }
    }

    private var cameraLayer: some View {
        Group {
            #if targetEnvironment(simulator)
            simulatorViewfinder
            #else
            ARSessionPreviewView(session: model.arSession)
            #endif
        }
    }

    /// A dark stand-in for the live feed in the Simulator, so the Liquid Glass
    /// overlays read the same as they will over a real camera.
    private var simulatorViewfinder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.08)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: TPCSpacing.sm) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 40, weight: .regular))
                Text("Live camera preview runs on a physical iPhone")
                    .font(TPCFont.footnote)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(TPCSpacing.xl)
        }
    }

    /// Center framing reticle (like the camera's focus mark) — tells the user
    /// where to aim without instructions.
    private var reticle: some View {
        Image(systemName: "viewfinder")
            .font(.system(size: 128, weight: .ultraLight))
            .foregroundStyle(.white.opacity(isCapturing ? 0.15 : 0.35))
    }

    private var captureCluster: some View {
        VStack(spacing: TPCSpacing.md) {
            instructionPill
            shutter
            Text(isCapturing ? "Keep holding…" : "Hold to Scan")
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(.white)
        }
    }

    private var instructionPill: some View {
        HStack(spacing: TPCSpacing.xs) {
            Image(systemName: isCapturing ? "arrow.trianglehead.2.clockwise.rotate.90" : "hand.tap.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(isCapturing
                 ? "Keep circling the plate slowly"
                 : "Hold the shutter and slowly circle your plate")
                .font(TPCFont.captionEmphasized)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, TPCSpacing.md)
        .padding(.vertical, TPCSpacing.xs)
        .glassEffect(in: Capsule())
    }

    private var shutter: some View {
        ZStack {
            Circle()
                .stroke(.white, lineWidth: 5)
                .frame(width: 88, height: 88)
            if case .capturing(let progress) = model.stage {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(TPCColor.brand, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(TPCColor.brand)
                    .frame(width: 60, height: 60)
            } else {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
            }
        }
        .contentShape(Circle())
        // Standard press-and-hold: `onChanged` on press-down (idempotent while
        // capturing), `onEnded` on release.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressShutter() }
                .onEnded { _ in releaseShutter() }
        )
        .accessibilityLabel("Hold to scan")
        .accessibilityHint("Press and hold, then slowly move around the plate.")
    }

    private func pressShutter() {
        #if !targetEnvironment(simulator)
        model.beginHold()
        #endif
    }

    private func releaseShutter() {
        #if targetEnvironment(simulator)
        model.simulateReview()
        #else
        model.endHold()
        #endif
    }

    // MARK: - Screen 2: Review

    private var reviewScreen: some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar(onBack: { model.retake() }, tint: TPCColor.textPrimary)
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.top, TPCSpacing.sm)

                ScrollView {
                    VStack(spacing: TPCSpacing.lg) {
                        videoPreview
                        detailsBar
                    }
                    .padding(.top, TPCSpacing.md)
                    .padding(.bottom, TPCSpacing.lg)
                }

                reviewActions
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.bottom, TPCSpacing.lg)
            }
        }
    }

    private var videoPreview: some View {
        Group {
            if model.previewImages.isEmpty {
                ZStack {
                    TPCColor.fillNeutral
                    VStack(spacing: TPCSpacing.sm) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 38, weight: .regular))
                        Text("Your capture plays here on a physical iPhone")
                            .font(TPCFont.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(TPCColor.textSecondary)
                    .padding(TPCSpacing.lg)
                }
            } else {
                Image(uiImage: model.previewImages[safe: previewIndex] ?? model.previewImages[0])
                    .resizable()
                    .scaledToFill()
                    .task {
                        // Cycle the selected frames as a lightweight looping
                        // playback of the captured arc.
                        while !Task.isCancelled, model.previewImages.count > 1 {
                            try? await Task.sleep(for: .milliseconds(350))
                            previewIndex = (previewIndex + 1) % model.previewImages.count
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous))
        .overlay(alignment: .bottom) {
            HStack(spacing: TPCSpacing.xxs) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 12, weight: .semibold))
                Text("3D capture")
                    .font(TPCFont.captionEmphasized)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, TPCSpacing.sm)
            .padding(.vertical, 6)
            .glassEffect(in: Capsule())
            .padding(.bottom, TPCSpacing.md)
        }
        .rivaSurfaceOutline(cornerRadius: TPCRadius.card)
        .padding(.horizontal, TPCSpacing.screenMargin)
    }

    /// One free-text bar (unstructured): the user describes the dish however
    /// they like. Optional — Proceed works with it empty.
    private var detailsBar: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
            Text("Add details")
                .rivaOverline()
            TextField(
                "e.g. grilled chicken, about 150 g, cooked in olive oil",
                text: $model.details,
                axis: .vertical
            )
            .lineLimit(1...3)
            .font(TPCFont.body)
            .foregroundStyle(TPCColor.textPrimary)
            .padding(.horizontal, TPCSpacing.md)
            .padding(.vertical, 14)
            .background(
                TPCColor.fillNeutral,
                in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
            )
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
    }

    private var reviewActions: some View {
        HStack(spacing: TPCSpacing.sm) {
            Button { model.retake() } label: {
                Text("Retake")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TPCColor.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        TPCColor.brandWash,
                        in: RoundedRectangle(cornerRadius: TPCRadius.control, style: .continuous)
                    )
            }
            .buttonStyle(.plain)

            Button("Proceed") { model.proceed() }
                .buttonStyle(.rivaPrimary)
        }
    }

    // MARK: - Shared chrome

    /// Aligned header used on both screens: back button (top-left), then the
    /// "TPC Snap V3" title + 3D badge. `tint` flips to white over the camera.
    private func topBar(onBack: @escaping () -> Void, tint: Color) -> some View {
        HStack(spacing: TPCSpacing.sm) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .glassEffect(in: Circle())
            }
            .accessibilityLabel("Back")

            HStack(spacing: TPCSpacing.xs) {
                Text("TPC Snap V3")
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(tint)
                RivaBadge(text: "3D", style: .brand)
            }

            Spacer()
        }
    }

    // MARK: - Processing

    /// Staged progress (upload → identify → measure) instead of a bare
    /// spinner — the volumetric pipeline typically takes 20-30s.
    private var processingScreen: some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()
            VStack(spacing: TPCSpacing.lg) {
                ProgressView().scaleEffect(1.2)
                Text(model.processingStep.rawValue)
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textPrimary)
                    .multilineTextAlignment(.center)
                RivaProgressBar(progress: model.processingStep.progress)
                    .frame(width: 160)
                Text("This can take up to 30 seconds.")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
            }
            .padding(.horizontal, TPCSpacing.xl)
        }
    }

    // MARK: - Result / saving / saved / error

    /// Small "experimental" framing shown above the result card — D3's
    /// required signal that a volumetric measurement is a beta estimate,
    /// not a claim of precision, and needs the user's own eyes before it's
    /// logged.
    private var experimentalNotice: some View {
        HStack(alignment: .top, spacing: TPCSpacing.xs) {
            Image(systemName: "flask")
                .font(.system(size: 13, weight: .semibold))
            Text("This one is experimental. Have a quick look at the portion before you log it.")
                .font(TPCFont.footnote)
        }
        .foregroundStyle(TPCColor.textSecondary)
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.top, TPCSpacing.xs)
    }

    private func resultScreen(_ scan: ScanResult) -> some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar(onBack: { model.retake() }, tint: TPCColor.textPrimary)
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.top, TPCSpacing.sm)
                experimentalNotice
                ScanResultCard(
                    scan: scan,
                    errorMessage: model.confirmError,
                    isSaving: false,
                    // No replacement service: the volumetric beta reviews a
                    // portion, not a food list, so its rows stay read-only.
                    onAccept: { _ in Task { await model.confirmAndLog() } },
                    onScanAgain: { model.retake() }
                )
            }
        }
    }

    private func savingScreen(_ scan: ScanResult) -> some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar(onBack: { model.retake() }, tint: TPCColor.textPrimary)
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.top, TPCSpacing.sm)
                experimentalNotice
                ScanResultCard(
                    scan: scan,
                    errorMessage: nil,
                    isSaving: true,
                    onAccept: { _ in },
                    onScanAgain: {}
                )
            }
        }
    }

    private func savedScreen(_ totals: DayTotals) -> some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()
            VStack(spacing: TPCSpacing.lg) {
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(TPCColor.textOnBrand)
                    .frame(width: 76, height: 76)
                    .background(TPCColor.brand, in: Circle())
                VStack(spacing: TPCSpacing.xs) {
                    Text("All set")
                        .font(TPCFont.sectionTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text("That puts you at \(totals.calories.formatted()) kcal and \(totals.proteinGrams)g of protein today.")
                        .font(TPCFont.body)
                        .foregroundStyle(TPCColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TPCSpacing.xl)
                }
                Spacer()
                Button("Done") { close() }
                    .buttonStyle(.rivaPrimary)
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.bottom, TPCSpacing.lg)
            }
        }
    }

    private func errorScreen(_ message: String) -> some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar(onBack: { model.retake() }, tint: TPCColor.textPrimary)
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.top, TPCSpacing.sm)
                Spacer()
                ErrorStateView(message: message, onRetry: { model.retake() })
                Spacer()
            }
        }
    }

    // MARK: - Tier C (unsupported physical device)

    private var unsupportedScreen: some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()
            VStack(spacing: TPCSpacing.lg) {
                topBar(onBack: close, tint: TPCColor.textPrimary)
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.top, TPCSpacing.sm)
                Spacer()
                DetailEmptyState(
                    systemImage: "arkit",
                    message: "TPC Snap V3 needs a device with ARKit. Build to a physical iPhone to try it."
                )
                Spacer()
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Thin camera-passthrough surface for the AR session `ARFoodCaptureController`
/// already owns and configures; this view never creates or configures a
/// session itself.
private struct ARSessionPreviewView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = true
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
