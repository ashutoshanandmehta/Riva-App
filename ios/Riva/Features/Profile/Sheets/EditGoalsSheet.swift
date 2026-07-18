import SwiftUI

/// Edit the daily nutrition goals: protein, carbs, fiber, and water.
struct EditGoalsSheet: View {
    let onClose: () -> Void

    @State private var model: EditGoalsViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: EditGoalsViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            AccountSheetHeader(sheet: .editGoals)

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
                    label: "Protein",
                    prompt: "100",
                    text: $model.proteinText,
                    unit: "g",
                    keyboard: .numberPad
                )
                AccountLabeledField(
                    label: "Carbs",
                    prompt: "150",
                    text: $model.carbText,
                    unit: "g",
                    keyboard: .numberPad
                )
            }
            HStack(alignment: .top, spacing: RivaSpacing.sm) {
                AccountLabeledField(
                    label: "Fiber",
                    prompt: "28",
                    text: $model.fiberText,
                    unit: "g",
                    keyboard: .numberPad
                )
                AccountLabeledField(
                    label: "Water",
                    prompt: "64",
                    text: $model.waterText,
                    unit: "oz",
                    keyboard: .numberPad
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

/// Prefills the nutrition goals and saves the edited values.
@MainActor
@Observable
final class EditGoalsViewModel {

    enum Phase: Equatable {
        case loading
        case failed(String)
        case editing
        case saving
        case saved(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var errorMessage: String?

    var proteinText = ""
    var carbText = ""
    var fiberText = ""
    var waterText = ""

    private let account: any AccountRepository

    init(account: any AccountRepository) {
        self.account = account
    }

    func load() async {
        phase = .loading
        do {
            let goals = try await account.me().nutritionGoals
            proteinText = String(goals.proteinGoal)
            carbText = String(goals.carbGoal)
            fiberText = String(goals.fiberGoal)
            waterText = String(goals.waterGoal)
            phase = .editing
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            phase = .failed("Could not load your goals.")
        }
    }

    var canSave: Bool {
        phase == .editing
            && parsed(proteinText) != nil
            && parsed(carbText) != nil
            && parsed(fiberText) != nil
            && parsed(waterText) != nil
    }

    func save() async {
        guard canSave else { return }
        phase = .saving
        errorMessage = nil
        let update = GoalsUpdate(
            proteinGoal: parsed(proteinText),
            carbGoal: parsed(carbText),
            fiberGoal: parsed(fiberText),
            waterGoal: parsed(waterText)
        )
        do {
            _ = try await account.updateGoals(update)
            phase = .saved("Goals saved.")
        } catch {
            phase = .editing
            errorMessage = "Could not save. Try again."
        }
    }

    private func parsed(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)),
              (1...999).contains(value) else { return nil }
        return value
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        EditGoalsSheet(account: MockAccountRepository()) {}
    }
}
