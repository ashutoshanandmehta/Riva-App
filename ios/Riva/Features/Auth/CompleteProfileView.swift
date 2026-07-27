import SwiftUI

/// Right after account creation: the details that make targets and
/// reminders personal. Everything here is optional except the name.
struct CompleteProfileView: View {
    @Bindable var model: AuthModel

    @State private var name = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -40, to: Date()) ?? Date()
    @State private var gender: String?
    @State private var heightText = ""
    @State private var startWeightText = ""
    @State private var goalWeightText = ""

    private static let genders: [(code: String, label: String)] = [
        ("female", "Female"),
        ("male", "Male"),
        ("non-binary", "Non binary"),
        ("prefer-not-to-say", "Prefer not to say"),
    ]

    var body: some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: TPCSpacing.md) {
                        VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                            Text("Complete your profile")
                                .font(TPCFont.screenTitle)
                                .foregroundStyle(TPCColor.textPrimary)
                            Text("This helps TPC personalize your targets, doses, and reminders. You can change everything later.")
                                .font(TPCFont.body)
                                .foregroundStyle(TPCColor.textSecondary)
                        }
                        .padding(.top, TPCSpacing.lg)

                        labeled("Your name") {
                            TextField("Name", text: $name)
                                .textContentType(.givenName)
                        }

                        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                            Toggle(isOn: $hasBirthDate.animation()) {
                                Text("Date of birth")
                                    .rivaOverline()
                            }
                            .tint(TPCColor.brand)
                            if hasBirthDate {
                                DatePicker("", selection: $birthDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            }
                        }

                        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                            Text("Gender")
                                .rivaOverline()
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: TPCSpacing.xs
                            ) {
                                ForEach(Self.genders, id: \.code) { option in
                                    chip(option.label, isSelected: gender == option.code) {
                                        gender = gender == option.code ? nil : option.code
                                    }
                                }
                            }
                        }

                        labeled("Height (inches)") {
                            TextField("65", text: $heightText)
                                .keyboardType(.decimalPad)
                        }
                        labeled("Current weight (lbs)") {
                            TextField("184", text: $startWeightText)
                                .keyboardType(.decimalPad)
                        }
                        labeled("Goal weight (lbs)") {
                            TextField("160", text: $goalWeightText)
                                .keyboardType(.decimalPad)
                        }

                        if let notice = model.notice {
                            Text(notice)
                                .font(TPCFont.footnote)
                                .foregroundStyle(TPCColor.danger)
                        }
                    }
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.bottom, TPCSpacing.xl)
                }

                VStack(spacing: TPCSpacing.xs) {
                    Button {
                        Task { await model.completeProfile(buildUpdate()) }
                    } label: {
                        if model.isWorking {
                            ProgressView().tint(TPCColor.textOnBrand)
                        } else {
                            Text("Finish")
                        }
                    }
                    .buttonStyle(.rivaPrimary)
                    .disabled(model.isWorking || name.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Skip for now") { model.skipProfileForNow() }
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(TPCColor.brand)
                }
                .padding(.horizontal, TPCSpacing.screenMargin)
                .padding(.vertical, TPCSpacing.sm)
                .background(TPCColor.background)
            }
        }
    }

    private func buildUpdate() -> ProfileUpdate {
        var update = ProfileUpdate()
        update.name = name.trimmingCharacters(in: .whitespaces)
        if hasBirthDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            update.dateOfBirth = formatter.string(from: birthDate)
        }
        update.gender = gender
        update.heightInches = Double(heightText.trimmingCharacters(in: .whitespaces))
        update.startWeight = Double(startWeightText.trimmingCharacters(in: .whitespaces))
        update.goalWeight = Double(goalWeightText.trimmingCharacters(in: .whitespaces))
        // Keep the account's calendar days aligned with the device.
        update.timezone = TimeZone.current.identifier
        return update
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
            Text(title)
                .rivaOverline()
            content()
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textPrimary)
                .padding(.horizontal, TPCSpacing.md)
                .padding(.vertical, 12)
                .background(
                    TPCColor.fillNeutral,
                    in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
                )
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(isSelected ? TPCColor.textOnBrand : TPCColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isSelected ? TPCColor.brandDeep : TPCColor.fillNeutral,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CompleteProfileView(model: AuthModel(
        repository: MockAuthRepository(),
        account: MockAccountRepository()
    ))
}
