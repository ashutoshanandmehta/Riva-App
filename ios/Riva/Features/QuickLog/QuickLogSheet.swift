import SwiftUI

/// The shared quick-log sheet: one presentation shell, per-kind form
/// content, a saving state, and a brief confirmation before dismissing.
struct QuickLogSheet: View {
    let onClose: () -> Void

    @State private var model: QuickLogViewModel
    @FocusState private var isFieldFocused: Bool

    init(kind: QuickLog, repository: any LogRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: QuickLogViewModel(kind: kind, repository: repository))
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            header

            if case .saved(let message) = model.phase {
                savedContent(message)
            } else {
                formContent
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
        .presentationDetents([model.kind == .sideEffects ? .large : .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
        .onChange(of: model.phase) {
            guard case .saved = model.phase else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                onClose()
            }
        }
    }

    // MARK: Shell

    private var header: some View {
        VStack(spacing: RivaSpacing.sm) {
            Image(systemName: model.kind.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(RivaColor.brand)
                .frame(width: 56, height: 56)
                .background(RivaColor.brandWash, in: Circle())
            Text(model.kind.title)
                .font(RivaFont.sectionTitle)
                .foregroundStyle(RivaColor.textPrimary)
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

    private func savedContent(_ message: String) -> some View {
        VStack(spacing: RivaSpacing.md) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(RivaColor.textOnBrand)
                .frame(width: 56, height: 56)
                .background(RivaColor.brand, in: Circle())
            Text(message)
                .font(RivaFont.body)
                .foregroundStyle(RivaColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RivaSpacing.xl)
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

    private var shotForm: some View {
        VStack(spacing: RivaSpacing.md) {
            HStack(spacing: RivaSpacing.sm) {
                TextField("Medication", text: $model.medicationName)
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
                    .padding(.horizontal, RivaSpacing.md)
                    .padding(.vertical, 12)
                    .background(
                        RivaColor.fillNeutral,
                        in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
                    )

                HStack(spacing: 5) {
                    TextField("0.5", text: $model.doseText)
                        .keyboardType(.decimalPad)
                        .font(RivaFont.body)
                        .foregroundStyle(RivaColor.textPrimary)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                    Text("mg")
                        .font(RivaFont.metricUnit)
                        .foregroundStyle(RivaColor.textSecondary)
                }
                .padding(.horizontal, RivaSpacing.md)
                .padding(.vertical, 12)
                .background(
                    RivaColor.fillNeutral,
                    in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
                )
            }

            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Text("Injection site")
                    .rivaOverline()
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: RivaSpacing.xs
                ) {
                    ForEach(InjectionSite.allCases) { site in
                        selectableChip(site.title, isSelected: model.site == site) {
                            model.site = site
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Text("Comfort (optional)")
                    .rivaOverline()
                HStack(spacing: RivaSpacing.xs) {
                    ForEach(1...5, id: \.self) { rating in
                        Button {
                            model.comfortRating = model.comfortRating == rating ? nil : rating
                        } label: {
                            Text("\(rating)")
                                .font(RivaFont.captionEmphasized)
                                .foregroundStyle(
                                    model.comfortRating == rating
                                        ? RivaColor.textOnBrand : RivaColor.textSecondary
                                )
                                .frame(width: 40, height: 40)
                                .background(
                                    model.comfortRating == rating
                                        ? RivaColor.brandDeep : RivaColor.fillNeutral,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
    }

    private var sideEffectsForm: some View {
        ScrollView {
            VStack(spacing: RivaSpacing.xs) {
                Text("Select what you felt today. Severity is 1 mild to 5 severe.")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, RivaSpacing.xxs)

                ForEach(SideEffect.allCases) { effect in
                    sideEffectRow(effect)
                }
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
        }
    }

    private func sideEffectRow(_ effect: SideEffect) -> some View {
        let severity = model.severities[effect]
        return VStack(spacing: RivaSpacing.xs) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    model.toggle(effect)
                }
            } label: {
                HStack {
                    Text(effect.title)
                        .font(RivaFont.cardTitle)
                        .foregroundStyle(RivaColor.textPrimary)
                    Spacer()
                    Image(systemName: severity == nil ? "plus.circle" : "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(severity == nil ? RivaColor.textTertiary : RivaColor.brand)
                }
            }
            .buttonStyle(.plain)

            if let severity {
                HStack(spacing: RivaSpacing.xs) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            model.severities[effect] = level
                        } label: {
                            Text("\(level)")
                                .font(RivaFont.captionEmphasized)
                                .foregroundStyle(
                                    severity == level ? RivaColor.textOnBrand : RivaColor.textSecondary
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(
                                    severity == level ? RivaColor.brandDeep : RivaColor.fillNeutral,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(RivaSpacing.sm)
        .background(
            RivaColor.surface,
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
        )
        .rivaSurfaceOutline(cornerRadius: RivaRadius.tile)
    }

    private var sleepForm: some View {
        VStack(spacing: RivaSpacing.xs) {
            ForEach(SleepOption.all) { option in
                Button {
                    model.sleepCode = option.code
                } label: {
                    HStack {
                        Text(option.label)
                            .font(RivaFont.cardTitle)
                            .foregroundStyle(RivaColor.textPrimary)
                        Spacer()
                        Image(systemName: model.sleepCode == option.code
                            ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(model.sleepCode == option.code
                                ? RivaColor.brand : RivaColor.textTertiary)
                    }
                    .padding(RivaSpacing.sm)
                    .background(
                        RivaColor.surface,
                        in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
                    )
                    .rivaSurfaceOutline(cornerRadius: RivaRadius.tile)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
    }

    // MARK: Shared pieces

    private func metricField(
        text: Binding<String>,
        unit: String,
        prompt: String,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RivaSpacing.xs) {
            TextField(prompt, text: text)
                .keyboardType(keyboard)
                .font(RivaFont.metricXL)
                .foregroundStyle(RivaColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(width: 132)
                .focused($isFieldFocused)
                .onAppear { isFieldFocused = true }
            Text(unit)
                .font(RivaFont.metricUnit)
                .foregroundStyle(RivaColor.textSecondary)
        }
        .padding(.vertical, RivaSpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RivaColor.surface,
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
        )
        .rivaSurfaceOutline(cornerRadius: RivaRadius.tile)
        .padding(.horizontal, RivaSpacing.screenMargin)
    }

    private func selectableChip(
        _ title: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
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

#Preview("Shot") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickLogSheet(kind: .shot, repository: MockLogRepository()) {}
    }
}

#Preview("Side effects") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickLogSheet(kind: .sideEffects, repository: MockLogRepository()) {}
    }
}
