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
            TPCColor.background.ignoresSafeArea()

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
            Text("TPC Snap")
                .font(TPCFont.sectionTitle)
                .foregroundStyle(TPCColor.textPrimary)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TPCColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(TPCColor.fillNeutral, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.vertical, TPCSpacing.sm)
    }

    // MARK: Capture

    private var captureContent: some View {
        VStack(spacing: TPCSpacing.lg) {
            modePicker

            photoPanel

            if let message = model.errorMessage {
                Text(message)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TPCSpacing.lg)
            }

            Spacer()

            VStack(spacing: TPCSpacing.sm) {
                if model.photo != nil {
                    hintField
                    Button("Scan") { Task { await model.scan() } }
                        .buttonStyle(.rivaPrimary)
                    Button("Choose a different photo") { model.photo = nil }
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(TPCColor.brand)
                } else {
                    if CameraPicker.isAvailable {
                        Button("Take a photo") { isCameraPresented = true }
                            .buttonStyle(.rivaPrimary)
                    }
                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        Text("Choose from library")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TPCColor.brand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                TPCColor.brandWash,
                                in: RoundedRectangle(cornerRadius: TPCRadius.control, style: .continuous)
                            )
                    }
                }
            }
            .padding(.horizontal, TPCSpacing.screenMargin)
            .padding(.bottom, TPCSpacing.lg)
        }
        .padding(.top, TPCSpacing.xs)
    }

    private var hintField: some View {
        TextField("Add a hint (optional)", text: $model.hint)
            .font(TPCFont.body)
            .foregroundStyle(TPCColor.textPrimary)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .padding(.horizontal, TPCSpacing.md)
            .padding(.vertical, 12)
            .background(
                TPCColor.surface,
                in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
            )
            .rivaSurfaceOutline(cornerRadius: TPCRadius.tile)
    }

    private var modePicker: some View {
        HStack(spacing: TPCSpacing.xs) {
            ForEach(ScanMode.allCases) { mode in
                Button {
                    model.mode = mode
                } label: {
                    Text(mode.title)
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(model.mode == mode ? TPCColor.textOnBrand : TPCColor.textSecondary)
                        .padding(.horizontal, TPCSpacing.md)
                        .padding(.vertical, 8)
                        .background(
                            model.mode == mode ? TPCColor.brandDeep : TPCColor.fillNeutral,
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
                VStack(spacing: TPCSpacing.sm) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(TPCColor.brand)
                    Text("Point at a meal, a drink, or a glass of water")
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TPCSpacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TPCColor.surface)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous))
        .rivaSurfaceOutline(cornerRadius: TPCRadius.card)
        .padding(.horizontal, TPCSpacing.screenMargin)
    }

    // MARK: Scanning

    private var scanningContent: some View {
        VStack(spacing: TPCSpacing.lg) {
            if let photo = model.photo {
                Color.clear
                    .overlay {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                    )
                    .padding(.horizontal, TPCSpacing.screenMargin)
            }
            ProgressView()
            Text("Scanning your photo. This can take a few seconds.")
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textSecondary)
            Spacer()
        }
        .padding(.top, TPCSpacing.xs)
    }

    // MARK: Saved

    private func savedContent(totals: DayTotals, loggedWater: Bool) -> some View {
        VStack(spacing: TPCSpacing.lg) {
            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(TPCColor.textOnBrand)
                .frame(width: 76, height: 76)
                .background(TPCColor.brand, in: Circle())

            VStack(spacing: TPCSpacing.xs) {
                Text("Logged")
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text(summary(totals: totals, loggedWater: loggedWater))
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TPCSpacing.xl)
            }

            Spacer()

            VStack(spacing: TPCSpacing.sm) {
                Button("Done") { onClose() }
                    .buttonStyle(.rivaPrimary)
                Button("Scan something else") { model.scanAgain() }
                    .font(TPCFont.captionEmphasized)
                    .foregroundStyle(TPCColor.brand)
            }
            .padding(.horizontal, TPCSpacing.screenMargin)
            .padding(.bottom, TPCSpacing.lg)
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
