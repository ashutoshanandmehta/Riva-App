import SwiftUI

/// Edit the medication plan: name, current dose, and shot cadence.
struct DoseSettingsSheet: View {
    let onClose: () -> Void

    @State private var model: DoseSettingsViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: DoseSettingsViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            AccountSheetHeader(sheet: .doseSettings)

            switch model.phase {
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .failed(let message):
                AccountLoadFailedView(message: message) {
                    Task { await model.load() }
                }
            case .saved(let message):
                AccountSavedView(message: message)
            case .editing, .saving:
                form
                if let message = model.errorMessage {
                    Text(message)
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, RivaSpacing.lg)
                }
                Spacer(minLength: RivaSpacing.xs)
                saveButton
            }
        }
        .padding(.top, RivaSpacing.xl)
        .padding(.bottom, RivaSpacing.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
        .task { await model.load() }
        .onChange(of: model.phase) {
            guard case .saved = model.phase else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                onClose()
            }
        }
    }

    private var form: some View {
        VStack(spacing: RivaSpacing.md) {
            HStack(alignment: .top, spacing: RivaSpacing.sm) {
                AccountLabeledField(
                    label: "Medication",
                    prompt: "Semaglutide",
                    text: $model.medicationName
                )
                AccountLabeledField(
                    label: "Dose",
                    prompt: "0.5",
                    text: $model.doseText,
                    unit: "mg",
                    keyboard: .decimalPad
                )
                .frame(width: 128)
            }

            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Text("Cadence")
                    .rivaOverline()
                Stepper(value: $model.cadenceDays, in: 1...90) {
                    Text(model.cadenceLabel)
                        .font(RivaFont.body)
                        .foregroundStyle(RivaColor.textPrimary)
                }
                .padding(.horizontal, RivaSpacing.md)
                .padding(.vertical, 12)
                .background(
                    RivaColor.fillNeutral,
                    in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
                )
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
    }

    private var saveButton: some View {
        Button {
            Task { await model.save() }
        } label: {
            if model.phase == .saving {
                ProgressView().tint(RivaColor.textOnBrand)
            } else {
                Text("Save")
            }
        }
        .buttonStyle(.rivaPrimary)
        .disabled(!model.canSave || model.phase == .saving)
        .padding(.horizontal, RivaSpacing.screenMargin)
    }
}

/// Prefills the plan (or sensible defaults when none exists) and saves edits.
@MainActor
@Observable
final class DoseSettingsViewModel {

    enum Phase: Equatable {
        case loading
        case failed(String)
        case editing
        case saving
        case saved(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var errorMessage: String?

    var medicationName = "Semaglutide"
    var doseText = "0.5"
    var cadenceDays = 7

    private let account: any AccountRepository

    init(account: any AccountRepository) {
        self.account = account
    }

    var cadenceLabel: String {
        cadenceDays == 1 ? "Every day" : "Every \(cadenceDays) days"
    }

    func load() async {
        phase = .loading
        do {
            if let plan = try await account.me().plan {
                medicationName = plan.name
                doseText = RivaFormat.doseNumber(plan.currentDoseMg)
                cadenceDays = plan.cadenceDays
            }
            phase = .editing
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            phase = .failed("Could not load your plan.")
        }
    }

    var canSave: Bool {
        phase == .editing
            && !medicationName.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedDose != nil
    }

    func save() async {
        guard canSave else { return }
        phase = .saving
        errorMessage = nil
        let update = PlanUpdate(
            name: medicationName.trimmingCharacters(in: .whitespaces),
            currentDoseMg: parsedDose,
            cadenceDays: cadenceDays
        )
        do {
            _ = try await account.updatePlan(update)
            phase = .saved("Plan saved.")
        } catch {
            phase = .editing
            errorMessage = "Could not save. Try again."
        }
    }

    private var parsedDose: Double? {
        guard let value = Double(doseText.trimmingCharacters(in: .whitespaces)),
              value > 0, value <= 100 else { return nil }
        return value
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        DoseSettingsSheet(account: MockAccountRepository()) {}
    }
}
