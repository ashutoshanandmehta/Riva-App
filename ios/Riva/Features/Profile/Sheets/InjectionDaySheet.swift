import SwiftUI

/// Pick the weekly injection day. Saves a weekly cadence with a
/// "Weekly on {Day}" reminder description.
struct InjectionDaySheet: View {
    let onClose: () -> Void

    @State private var model: InjectionDayViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: InjectionDayViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            AccountSheetHeader(sheet: .injectionDay)

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
                dayGrid
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

    private var dayGrid: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text("Your weekly shot day")
                .rivaOverline()
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: RivaSpacing.xs
            ) {
                ForEach(RivaWeekday.names, id: \.self) { day in
                    AccountChip(title: day, isSelected: model.selectedDay == day) {
                        model.selectedDay = day
                    }
                }
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

/// Preselects the day parsed from the plan's reminder text, then saves the
/// chosen day as a weekly schedule.
@MainActor
@Observable
final class InjectionDayViewModel {

    enum Phase: Equatable {
        case loading
        case failed(String)
        case editing
        case saving
        case saved(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var errorMessage: String?

    var selectedDay: String?

    private let account: any AccountRepository

    init(account: any AccountRepository) {
        self.account = account
    }

    func load() async {
        phase = .loading
        do {
            let plan = try await account.me().plan
            selectedDay = RivaWeekday.name(in: plan?.reminderDescription)
            phase = .editing
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            phase = .failed("Could not load your plan.")
        }
    }

    var canSave: Bool {
        phase == .editing && selectedDay != nil
    }

    func save() async {
        guard canSave, let day = selectedDay else { return }
        phase = .saving
        errorMessage = nil
        let update = PlanUpdate(cadenceDays: 7, reminderDescription: "Weekly on \(day)")
        do {
            _ = try await account.updatePlan(update)
            phase = .saved("Injection day saved.")
        } catch {
            phase = .editing
            errorMessage = "Could not save. Try again."
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        InjectionDaySheet(account: MockAccountRepository()) {}
    }
}
