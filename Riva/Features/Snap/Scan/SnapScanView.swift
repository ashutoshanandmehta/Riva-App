import PhotosUI
import SwiftUI

/// The snap scan flow, presented full screen from the radial menu: capture
/// or pick a photo, scan it, review, accept. The user is already signed in
/// by the time this appears.
struct SnapScanView: View {
    let onClose: () -> Void

    @State private var model: SnapScanViewModel
    @State private var libraryItem: PhotosPickerItem?
    @State private var isCameraPresented = false

    init(mode: ScanMode,
         scanRepository: any ScanRepository,
         onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: SnapScanViewModel(
            mode: mode,
            scanRepository: scanRepository
        ))
    }

    var body: some View {
        ZStack {
            RivaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                switch model.stage {
                case .capture:
                    captureContent
                case .scanning:
                    scanningContent
                case .result(let scan):
                    ScanResultCard(
                        scan: scan,
                        errorMessage: model.errorMessage,
                        isSaving: false,
                        onAccept: { Task { await model.accept() } },
                        onScanAgain: { model.scanAgain() }
                    )
                case .saving(let scan):
                    ScanResultCard(
                        scan: scan,
                        errorMessage: nil,
                        isSaving: true,
                        onAccept: {},
                        onScanAgain: {}
                    )
                case .saved(let totals, let loggedWater):
                    savedContent(totals: totals, loggedWater: loggedWater)
                }
            }
        }
        .task { await model.runDebugAutoTestIfRequested() }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { model.photo = $0 }
                .ignoresSafeArea()
        }
        .onChange(of: libraryItem) {
            guard let item = libraryItem else { return }
            libraryItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    model.photo = image
                }
            }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Text("Riva Snap")
                .font(RivaFont.sectionTitle)
                .foregroundStyle(RivaColor.textPrimary)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RivaColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(RivaColor.fillNeutral, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.vertical, RivaSpacing.sm)
    }

    // MARK: Capture

    private var captureContent: some View {
        VStack(spacing: RivaSpacing.lg) {
            modePicker

            photoPanel

            if let message = model.errorMessage {
                Text(message)
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RivaSpacing.lg)
            }

            Spacer()

            VStack(spacing: RivaSpacing.sm) {
                if model.photo != nil {
                    Button("Scan") { Task { await model.scan() } }
                        .buttonStyle(.rivaPrimary)
                    Button("Choose a different photo") { model.photo = nil }
                        .font(RivaFont.captionEmphasized)
                        .foregroundStyle(RivaColor.brand)
                } else {
                    if CameraPicker.isAvailable {
                        Button("Take a photo") { isCameraPresented = true }
                            .buttonStyle(.rivaPrimary)
                    }
                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        Text("Choose from library")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(RivaColor.brand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RivaColor.brandWash,
                                in: RoundedRectangle(cornerRadius: RivaRadius.control, style: .continuous)
                            )
                    }
                }
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
            .padding(.bottom, RivaSpacing.lg)
        }
        .padding(.top, RivaSpacing.xs)
    }

    private var modePicker: some View {
        HStack(spacing: RivaSpacing.xs) {
            ForEach(ScanMode.allCases) { mode in
                Button {
                    model.mode = mode
                } label: {
                    Text(mode.title)
                        .font(RivaFont.captionEmphasized)
                        .foregroundStyle(model.mode == mode ? RivaColor.textOnBrand : RivaColor.textSecondary)
                        .padding(.horizontal, RivaSpacing.md)
                        .padding(.vertical, 8)
                        .background(
                            model.mode == mode ? RivaColor.brandDeep : RivaColor.fillNeutral,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var photoPanel: some View {
        Group {
            if let photo = model.photo {
                // The image lives in an overlay so its natural size can never
                // widen the layout; the clear base defines the panel bounds.
                Color.clear
                    .overlay {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    }
            } else {
                VStack(spacing: RivaSpacing.sm) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(RivaColor.brand)
                    Text("Point at a meal, a drink, or a glass of water")
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, RivaSpacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RivaColor.surface)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous))
        .rivaSurfaceOutline(cornerRadius: RivaRadius.card)
        .padding(.horizontal, RivaSpacing.screenMargin)
    }

    // MARK: Scanning

    private var scanningContent: some View {
        VStack(spacing: RivaSpacing.lg) {
            if let photo = model.photo {
                Color.clear
                    .overlay {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                    )
                    .padding(.horizontal, RivaSpacing.screenMargin)
            }
            ProgressView()
            Text("Scanning your photo. This can take a few seconds.")
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textSecondary)
            Spacer()
        }
        .padding(.top, RivaSpacing.xs)
    }

    // MARK: Saved

    private func savedContent(totals: DayTotals, loggedWater: Bool) -> some View {
        VStack(spacing: RivaSpacing.lg) {
            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(RivaColor.textOnBrand)
                .frame(width: 76, height: 76)
                .background(RivaColor.brand, in: Circle())

            VStack(spacing: RivaSpacing.xs) {
                Text("Logged")
                    .font(RivaFont.sectionTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text(summary(totals: totals, loggedWater: loggedWater))
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RivaSpacing.xl)
            }

            Spacer()

            VStack(spacing: RivaSpacing.sm) {
                Button("Done") { onClose() }
                    .buttonStyle(.rivaPrimary)
                Button("Scan something else") { model.scanAgain() }
                    .font(RivaFont.captionEmphasized)
                    .foregroundStyle(RivaColor.brand)
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
            .padding(.bottom, RivaSpacing.lg)
        }
    }

    private func summary(totals: DayTotals, loggedWater: Bool) -> String {
        if loggedWater {
            return "Today so far: \(totals.waterOunces) oz of water."
        }
        return "Today so far: \(totals.calories.formatted()) kcal and \(totals.proteinGrams)g protein."
    }
}

#Preview("Scan flow") {
    SnapScanView(
        mode: .food,
        scanRepository: MockScanRepository()
    ) {}
}
