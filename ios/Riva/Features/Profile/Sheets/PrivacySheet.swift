import SwiftUI

/// How data is stored, plus the two controls that matter: export a full
/// copy, or erase everything and start the device over.
struct PrivacySheet: View {
    let onClose: () -> Void

    @State private var model: PrivacyViewModel
    @State private var isDeleteConfirmPresented = false

    init(account: any AccountRepository, auth: any AuthRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: PrivacyViewModel(account: account, auth: auth))
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            AccountSheetHeader(sheet: .privacy)

            if case .deleted(let message) = model.phase {
                AccountSavedView(message: message)
            } else {
                content
            }
        }
        .padding(.top, RivaSpacing.xl)
        .padding(.bottom, RivaSpacing.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
        .onChange(of: model.phase) {
            guard case .deleted = model.phase else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                onClose()
            }
        }
        .alert("Delete my data?", isPresented: $isDeleteConfirmPresented) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this device's logs and profile.")
        }
    }

    private var content: some View {
        VStack(spacing: RivaSpacing.md) {
            Text("Your data lives in a private account in the Riva backend, isolated per user and reachable only from this device's sign in. It is never sold or shared for advertising. You can take a full copy or erase everything whenever you like.")
                .font(RivaFont.body)
                .foregroundStyle(RivaColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RivaSpacing.screenMargin)

            if let message = model.errorMessage {
                Text(message)
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RivaSpacing.lg)
            }

            Spacer(minLength: RivaSpacing.xs)

            exportButton
            deleteButton
        }
    }

    private var exportButton: some View {
        Group {
            if let url = model.exportURL {
                ShareLink(item: url) {
                    HStack(spacing: RivaSpacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share riva-export.json")
                    }
                }
                .buttonStyle(.rivaPrimary)
            } else {
                Button {
                    Task { await model.export() }
                } label: {
                    if model.phase == .exporting {
                        ProgressView().tint(RivaColor.textOnBrand)
                    } else {
                        Text("Export my data")
                    }
                }
                .buttonStyle(.rivaPrimary)
                .disabled(model.phase != .idle)
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
    }

    private var deleteButton: some View {
        Button {
            isDeleteConfirmPresented = true
        } label: {
            if model.phase == .deleting {
                ProgressView().tint(RivaColor.danger)
            } else {
                Text("Delete my data")
            }
        }
        .buttonStyle(.rivaDestructive)
        .disabled(model.phase != .idle)
        .padding(.horizontal, RivaSpacing.screenMargin)
    }
}

/// Drives export to a shareable file and full account deletion.
@MainActor
@Observable
final class PrivacyViewModel {

    enum Phase: Equatable {
        case idle
        case exporting
        case deleting
        case deleted(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var exportURL: URL?

    private let account: any AccountRepository
    private let auth: any AuthRepository

    init(account: any AccountRepository, auth: any AuthRepository) {
        self.account = account
        self.auth = auth
    }

    func export() async {
        guard phase == .idle else { return }
        phase = .exporting
        errorMessage = nil
        do {
            let data = try await account.exportData()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("riva-export.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            phase = .idle
        } catch {
            phase = .idle
            errorMessage = "Could not export your data. Try again."
        }
    }

    func deleteEverything() async {
        guard phase == .idle else { return }
        phase = .deleting
        errorMessage = nil
        do {
            try await account.deleteAccount()
            await auth.resetIdentity()
            phase = .deleted("Everything is deleted. This device starts fresh.")
        } catch {
            phase = .idle
            errorMessage = "Could not delete your data. Try again."
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PrivacySheet(account: MockAccountRepository(), auth: MockAuthRepository()) {}
    }
}
