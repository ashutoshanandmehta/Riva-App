import SwiftUI

/// Edit name, date of birth, gender, height, and weight goals. Prefills from
/// the server and sends only the fields the user actually changed.
struct EditProfileSheet: View {
    let onClose: () -> Void

    @State private var model: EditProfileViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: EditProfileViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            AccountSheetHeader(sheet: .editProfile)

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
                saveButton
            }
        }
        .padding(.top, RivaSpacing.xl)
        .padding(.bottom, RivaSpacing.lg)
        .presentationDetents([.large])
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
        ScrollView {
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                AccountLabeledField(label: "Name", prompt: "Your name", text: $model.name)

                dateOfBirthSection

                genderSection

                AccountLabeledField(
                    label: "Height",
                    prompt: "65",
                    text: $model.heightText,
                    unit: "in",
                    keyboard: .decimalPad
                )

                HStack(alignment: .top, spacing: RivaSpacing.sm) {
                    AccountLabeledField(
                        label: "Start weight",
                        prompt: "192",
                        text: $model.startWeightText,
                        unit: "lbs",
                        keyboard: .decimalPad
                    )
                    AccountLabeledField(
                        label: "Goal weight",
                        prompt: "158",
                        text: $model.goalWeightText,
                        unit: "lbs",
                        keyboard: .decimalPad
                    )
                }
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
            .padding(.bottom, RivaSpacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var dateOfBirthSection: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text("Date of birth")
                .rivaOverline()
            VStack(spacing: RivaSpacing.xs) {
                Toggle("Share date of birth", isOn: $model.hasDateOfBirth.animation())
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
                    .tint(RivaColor.brand)
                if model.hasDateOfBirth {
                    DatePicker(
                        "Date of birth",
                        selection: $model.dateOfBirth,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
                    .tint(RivaColor.brand)
                }
            }
            .padding(.horizontal, RivaSpacing.md)
            .padding(.vertical, 12)
            .background(
                RivaColor.fillNeutral,
                in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
            )
        }
    }

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text("Gender")
                .rivaOverline()
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: RivaSpacing.xs
            ) {
                ForEach(EditProfileViewModel.genderOptions, id: \.value) { option in
                    AccountChip(title: option.label, isSelected: model.gender == option.value) {
                        model.gender = option.value
                    }
                }
            }
        }
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

/// Loads the current profile, tracks edits, and saves only what changed.
@MainActor
@Observable
final class EditProfileViewModel {

    enum Phase: Equatable {
        case loading
        case failed(String)
        case editing
        case saving
        case saved(String)
    }

    struct GenderOption {
        let label: String
        let value: String
    }

    static let genderOptions = [
        GenderOption(label: "Female", value: "female"),
        GenderOption(label: "Male", value: "male"),
        GenderOption(label: "Non binary", value: "non-binary"),
        GenderOption(label: "Prefer not to say", value: "prefer-not-to-say"),
    ]

    private(set) var phase: Phase = .loading
    private(set) var errorMessage: String?

    var name = ""
    var hasDateOfBirth = false
    var dateOfBirth = AccountDates.day("1990-01-01") ?? .now
    var gender: String?
    var heightText = ""
    var startWeightText = ""
    var goalWeightText = ""

    private var loaded: AccountProfile?
    private let account: any AccountRepository

    init(account: any AccountRepository) {
        self.account = account
    }

    func load() async {
        phase = .loading
        do {
            let profile = try await account.me().profile
            loaded = profile
            name = profile.name
            if let day = profile.dateOfBirth.flatMap(AccountDates.day) {
                hasDateOfBirth = true
                dateOfBirth = day
            }
            gender = profile.gender
            heightText = Self.decimalText(profile.heightInches)
            startWeightText = Self.decimalText(profile.startWeight)
            goalWeightText = Self.decimalText(profile.goalWeight)
            phase = .editing
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            phase = .failed("Could not load your profile.")
        }
    }

    var canSave: Bool {
        phase == .editing
            && fieldValue(heightText, range: 20...100) != .invalid
            && fieldValue(startWeightText, range: 20...1500) != .invalid
            && fieldValue(goalWeightText, range: 20...1500) != .invalid
    }

    func save() async {
        guard canSave else { return }
        phase = .saving
        errorMessage = nil

        var update = ProfileUpdate()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty, trimmedName != loaded?.name {
            update.name = trimmedName
        }
        if hasDateOfBirth {
            let day = AccountDates.dayString(dateOfBirth)
            if day != loaded?.dateOfBirth { update.dateOfBirth = day }
        }
        if let gender, gender != loaded?.gender {
            update.gender = gender
        }
        if case .value(let height) = fieldValue(heightText, range: 20...100),
           height != loaded?.heightInches {
            update.heightInches = height
        }
        if case .value(let start) = fieldValue(startWeightText, range: 20...1500),
           start != loaded?.startWeight {
            update.startWeight = start
        }
        if case .value(let goal) = fieldValue(goalWeightText, range: 20...1500),
           goal != loaded?.goalWeight {
            update.goalWeight = goal
        }
        // Always sent so the backend can localize daily rollups correctly.
        update.timezone = TimeZone.current.identifier

        do {
            _ = try await account.updateProfile(update)
            phase = .saved("Profile saved.")
        } catch {
            phase = .editing
            errorMessage = "Could not save. Try again."
        }
    }

    // MARK: Parsing

    private enum FieldValue: Equatable {
        case empty
        case value(Double)
        case invalid
    }

    private func fieldValue(_ text: String, range: ClosedRange<Double>) -> FieldValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        guard let value = Double(trimmed), range.contains(value) else { return .invalid }
        return .value(value)
    }

    private static func decimalText(_ value: Double?) -> String {
        guard let value else { return "" }
        return RivaFormat.doseNumber(value)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        EditProfileSheet(account: MockAccountRepository()) {}
    }
}
