import SwiftUI

/// The shared quick-log sheet: one presentation shell, per-kind form
/// content, a saving state, and a brief confirmation before dismissing.
struct QuickLogSheet: View {
    let onClose: (DayTotals?) -> Void

    @State private var model: QuickLogViewModel
    @FocusState private var isFieldFocused: Bool

    init(kind: QuickLog, repository: any LogRepository, onClose: @escaping (DayTotals?) -> Void) {
        self.onClose = onClose
        _model = State(initialValue: QuickLogViewModel(kind: kind, repository: repository))
    }

    var body: some View {
        VStack(spacing: TPCSpacing.lg) {
            header

            if case .saved(let message) = model.phase {
                savedContent(message)
            } else {
                formContent
                if let message = model.errorMessage {
                    Text(message)
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TPCSpacing.lg)
                }
                Spacer(minLength: TPCSpacing.xs)
                saveButton
            }
        }
        .padding(.top, TPCSpacing.xl)
        .padding(.bottom, TPCSpacing.lg)
        .presentationDetents([model.kind.needsTallSheet ? .large : .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(TPCColor.background)
        .onChange(of: model.phase) {
            guard case .saved = model.phase else { return }
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                onClose(model.savedTotals)
            }
        }
    }

    // MARK: Shell

    private var header: some View {
        VStack(spacing: TPCSpacing.sm) {
            Image(systemName: model.kind.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(TPCColor.brand)
                .frame(width: 56, height: 56)
                .background(TPCColor.brandWash, in: Circle())
            Text(model.kind.title)
                .font(TPCFont.sectionTitle)
                .foregroundStyle(TPCColor.textPrimary)
        }
    }

    private var saveButton: some View {
        Button {
            Task { await model.save() }
        } label: {
            if model.phase == .saving {
                ProgressView().tint(TPCColor.textOnBrand)
            } else {
                Text("Save")
            }
        }
        .buttonStyle(.rivaPrimary)
        .disabled(model.phase == .saving)
        .padding(.horizontal, TPCSpacing.screenMargin)
    }

    private func savedContent(_ message: String) -> some View {
        VStack(spacing: TPCSpacing.md) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(TPCColor.textOnBrand)
                .frame(width: 56, height: 56)
                .background(TPCColor.brand, in: Circle())
            Text(message)
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TPCSpacing.xl)
            Spacer()
        }
    }

    // MARK: Forms

    @ViewBuilder
    private var formContent: some View {
        switch model.kind {
        case .weight: weightForm
        case .shot: shotForm
        case .protein: proteinForm
        case .water: waterForm
        case .calories: caloriesForm
        case .sideEffects: sideEffectsForm
        case .sleep: sleepForm
        }
    }

    private var weightForm: some View {
        metricField(
            text: $model.weightText,
            unit: "lbs",
            prompt: "184.2",
            keyboard: .decimalPad
        )
    }

    private var proteinForm: some View {
        metricField(
            text: $model.proteinText,
            unit: "g",
            prompt: "30",
            keyboard: .numberPad
        )
    }

    private var waterForm: some View {
        VStack(spacing: TPCSpacing.sm) {
            metricField(
                text: $model.waterText,
                unit: "oz",
                prompt: "8",
                keyboard: .numberPad
            )

            Text("oz = fluid ounces. A standard glass is about 8 oz (≈ 240 ml).")
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TPCSpacing.screenMargin)
        }
    }

    private var caloriesForm: some View {
        metricField(
            text: $model.caloriesText,
            unit: "kcal",
            prompt: "250",
            keyboard: .numberPad
        )
    }

    private var shotForm: some View {
        VStack(spacing: TPCSpacing.md) {
            HStack(spacing: TPCSpacing.sm) {
                TextField("Medication", text: $model.medicationName)
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textPrimary)
                    .padding(.horizontal, TPCSpacing.md)
                    .padding(.vertical, 12)
                    .background(
                        TPCColor.fillNeutral,
                        in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
                    )
                    .overlay(invalidBorder(model.showValidation && model.isMedicationMissing))

                HStack(spacing: 5) {
                    TextField("0.5", text: $model.doseText)
                        .keyboardType(.decimalPad)
                        .font(TPCFont.body)
                        .foregroundStyle(TPCColor.textPrimary)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                    Text("mg")
                        .font(TPCFont.metricUnit)
                        .foregroundStyle(TPCColor.textSecondary)
                }
                .padding(.horizontal, TPCSpacing.md)
                .padding(.vertical, 12)
                .background(
                    TPCColor.fillNeutral,
                    in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
                )
                .overlay(invalidBorder(model.showValidation && model.isDoseMissing))
            }

            VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                Text("Injection site")
                    .rivaOverline(
                        model.showValidation && model.isSiteMissing
                            ? TPCColor.danger : TPCColor.textSecondary
                    )
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: TPCSpacing.xs
                ) {
                    ForEach(InjectionSite.allCases) { site in
                        selectableChip(site.title, isSelected: model.site == site) {
                            model.site = site
                        }
                    }
                }
                if model.showValidation && model.isSiteMissing {
                    Text("Select where you injected.")
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.danger)
                }
            }

            VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                Text("Comfort (optional)")
                    .rivaOverline()
                HStack(spacing: TPCSpacing.xs) {
                    ForEach(1...5, id: \.self) { rating in
                        Button {
                            model.comfortRating = model.comfortRating == rating ? nil : rating
                        } label: {
                            Text("\(rating)")
                                .font(TPCFont.captionEmphasized)
                                .foregroundStyle(
                                    model.comfortRating == rating
                                        ? TPCColor.textOnBrand : TPCColor.textSecondary
                                )
                                .frame(width: 40, height: 40)
                                .background(
                                    model.comfortRating == rating
                                        ? TPCColor.brandDeep : TPCColor.fillNeutral,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
    }

    private var sideEffectsForm: some View {
        ScrollView {
            VStack(spacing: TPCSpacing.xs) {
                Text("Select what you felt today. Severity is 1 mild to 5 severe.")
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, TPCSpacing.xxs)

                ForEach(SideEffect.allCases) { effect in
                    sideEffectRow(effect)
                }
            }
            .padding(.horizontal, TPCSpacing.screenMargin)
        }
    }

    private func sideEffectRow(_ effect: SideEffect) -> some View {
        let severity = model.severities[effect]
        return VStack(spacing: TPCSpacing.xs) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    model.toggle(effect)
                }
            } label: {
                HStack {
                    Text(effect.title)
                        .font(TPCFont.cardTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Spacer()
                    Image(systemName: severity == nil ? "plus.circle" : "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(severity == nil ? TPCColor.textTertiary : TPCColor.brand)
                }
            }
            .buttonStyle(.plain)

            if let severity {
                HStack(spacing: TPCSpacing.xs) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            model.severities[effect] = level
                        } label: {
                            Text("\(level)")
                                .font(TPCFont.captionEmphasized)
                                .foregroundStyle(
                                    severity == level ? TPCColor.textOnBrand : TPCColor.textSecondary
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(
                                    severity == level ? TPCColor.brandDeep : TPCColor.fillNeutral,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(TPCSpacing.sm)
        .background(
            TPCColor.surface,
            in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
        )
        .rivaSurfaceOutline(cornerRadius: TPCRadius.tile)
    }

    private var sleepForm: some View {
        VStack(spacing: TPCSpacing.xs) {
            ForEach(SleepOption.all) { option in
                Button {
                    model.sleepCode = option.code
                } label: {
                    HStack {
                        Text(option.label)
                            .font(TPCFont.cardTitle)
                            .foregroundStyle(TPCColor.textPrimary)
                        Spacer()
                        Image(systemName: model.sleepCode == option.code
                            ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(model.sleepCode == option.code
                                ? TPCColor.brand : TPCColor.textTertiary)
                    }
                    .padding(TPCSpacing.sm)
                    .background(
                        TPCColor.surface,
                        in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
                    )
                    .rivaSurfaceOutline(cornerRadius: TPCRadius.tile)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
    }

    // MARK: Shared pieces

    /// A red outline drawn over a field when it failed validation.
    private func invalidBorder(_ isInvalid: Bool) -> some View {
        RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
            .stroke(TPCColor.danger, lineWidth: isInvalid ? 1.5 : 0)
    }

    private func metricField(
        text: Binding<String>,
        unit: String,
        prompt: String,
        keyboard: UIKeyboardType
    ) -> some View {
        let isInvalid = model.showValidation && !model.canSave
        return HStack(alignment: .firstTextBaseline, spacing: TPCSpacing.xs) {
            TextField(prompt, text: text)
                .keyboardType(keyboard)
                .font(TPCFont.metricXL)
                .foregroundStyle(TPCColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(width: 132)
                .focused($isFieldFocused)
                .onAppear { isFieldFocused = true }
            Text(unit)
                .font(TPCFont.metricUnit)
                .foregroundStyle(TPCColor.textSecondary)
        }
        .padding(.vertical, TPCSpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            TPCColor.surface,
            in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
        )
        .rivaSurfaceOutline(cornerRadius: TPCRadius.tile)
        .overlay(invalidBorder(isInvalid))
        .padding(.horizontal, TPCSpacing.screenMargin)
    }

    private func selectableChip(
        _ title: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
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

#Preview("Shot") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickLogSheet(kind: .shot, repository: MockLogRepository()) { _ in }
    }
}

#Preview("Side effects") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickLogSheet(kind: .sideEffects, repository: MockLogRepository()) { _ in }
    }
}
