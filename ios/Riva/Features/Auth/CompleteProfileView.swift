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
            RivaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: RivaSpacing.md) {
                        VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                            Text("Complete your profile")
                                .font(RivaFont.screenTitle)
                                .foregroundStyle(RivaColor.textPrimary)
                            Text("This helps Riva personalize your targets, doses, and reminders. You can change everything later.")
                                .font(RivaFont.body)
                                .foregroundStyle(RivaColor.textSecondary)
                        }
                        .padding(.top, RivaSpacing.lg)

                        labeled("Your name") {
                            TextField("Name", text: $name)
                                .textContentType(.givenName)
                        }

                        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                            Toggle(isOn: $hasBirthDate.animation()) {
                                Text("Date of birth")
                                    .rivaOverline()
                            }
                            .tint(RivaColor.brand)
                            if hasBirthDate {
                                DatePicker("", selection: $birthDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            }
                        }

                        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                            Text("Gender")
                                .rivaOverline()
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: RivaSpacing.xs
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
                                .font(RivaFont.footnote)
                                .foregroundStyle(RivaColor.danger)
                        }
                    }
                    .padding(.horizontal, RivaSpacing.screenMargin)
                    .padding(.bottom, RivaSpacing.xl)
                }

                VStack(spacing: RivaSpacing.xs) {
                    Button {
                        Task { await model.completeProfile(buildUpdate()) }
                    } label: {
                        if model.isWorking {
                            ProgressView().tint(RivaColor.textOnBrand)
                        } else {
                            Text("Finish")
                        }
                    }
                    .buttonStyle(.rivaPrimary)
                    .disabled(model.isWorking || name.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Skip for now") { model.skipProfileForNow() }
                        .font(RivaFont.captionEmphasized)
                        .foregroundStyle(RivaColor.brand)
                }
                .padding(.horizontal, RivaSpacing.screenMargin)
                .padding(.vertical, RivaSpacing.sm)
                .background(RivaColor.background)
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
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text(title)
                .rivaOverline()
            content()
                .font(RivaFont.body)
                .foregroundStyle(RivaColor.textPrimary)
                .padding(.horizontal, RivaSpacing.md)
                .padding(.vertical, 12)
                .background(
                    RivaColor.fillNeutral,
                    in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
                )
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RivaFont.captionEmphasized)
                .foregroundStyle(isSelected ? RivaColor.textOnBrand : RivaColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isSelected ? RivaColor.brandDeep : RivaColor.fillNeutral,
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
