import SwiftUI

/// One sheet for both "Set a to-do" and "Edit to-do" — the draft carries an
/// id when editing, which is exactly what the upsert endpoint expects.
/// Reuses the account sheets' field, chip, and confirmation views.
struct TodoEditorSheet: View {
    @State private var draft: TodoDraft
    @State private var isSaving = false
    @State private var didSave = false

    private let isEditing: Bool
    private let notificationsDenied: Bool
    private let onSave: (TodoDraft) async -> Bool
    private let onDelete: (() async -> Void)?
    private let onClose: () -> Void

    /// `todo` nil creates; non-nil edits it (and reveals Delete).
    init(
        todo: Todo?,
        notificationsDenied: Bool,
        onSave: @escaping (TodoDraft) async -> Bool,
        onDelete: (() async -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        _draft = State(initialValue: todo.map { TodoDraft(todo: $0) } ?? TodoDraft())
        isEditing = todo != nil
        self.notificationsDenied = notificationsDenied
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            header

            if didSave {
                AccountSavedView(message: isEditing ? "To-do updated." : "To-do set.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: RivaSpacing.lg) {
                        AccountLabeledField(
                            label: "To-do",
                            prompt: "Log breakfast",
                            text: $draft.title
                        )
                        categoryPicker
                        repeatPicker
                        schedule
                        if notificationsDenied {
                            Text("Notifications for Riva are turned off. Allow them in Settings to be reminded.")
                                .font(RivaFont.footnote)
                                .foregroundStyle(RivaColor.textSecondary)
                        }
                    }
                    .padding(.horizontal, RivaSpacing.screenMargin)
                    .padding(.bottom, RivaSpacing.md)
                }
                actions
            }
        }
        .padding(.top, RivaSpacing.xl)
        .padding(.bottom, RivaSpacing.lg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
        .animation(.default, value: draft.repeatRule)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: RivaSpacing.sm) {
            Image(systemName: "checklist")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(RivaColor.brand)
                .frame(width: 56, height: 56)
                .background(RivaColor.brandWash, in: Circle())
            Text(isEditing ? "Edit to-do" : "Set a to-do")
                .font(RivaFont.sectionTitle)
                .foregroundStyle(RivaColor.textPrimary)
        }
    }

    // MARK: Fields

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text("Category")
                .rivaOverline()
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: RivaSpacing.xs
            ) {
                ForEach(TodoCategory.allCases) { category in
                    AccountChip(title: category.title, isSelected: draft.category == category) {
                        draft.category = category
                    }
                }
            }
            Text(hint(for: draft.category))
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textSecondary)
        }
    }

    private var repeatPicker: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text("Repeats")
                .rivaOverline()
            HStack(spacing: RivaSpacing.xs) {
                ForEach(TodoRepeat.allCases) { rule in
                    AccountChip(title: rule.title, isSelected: draft.repeatRule == rule) {
                        draft.repeatRule = rule
                    }
                }
            }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            DatePicker(
                "Remind me at",
                selection: $draft.time,
                displayedComponents: .hourAndMinute
            )
            if draft.repeatRule == .once {
                DatePicker(
                    "On",
                    selection: $draft.day,
                    in: Date.now.addingTimeInterval(-86_400)...,
                    displayedComponents: .date
                )
            }
        }
        .font(RivaFont.body)
        .foregroundStyle(RivaColor.textPrimary)
        .tint(RivaColor.brand)
        .padding(.horizontal, RivaSpacing.md)
        .padding(.vertical, 12)
        .background(
            RivaColor.fillNeutral,
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
        )
    }

    /// Says what tapping the to-do on the card will do, so the category is a
    /// real choice rather than a label.
    private func hint(for category: TodoCategory) -> String {
        switch category {
        case .food: "Tapping it opens the food scanner."
        case .water: "Tapping it opens the water scanner."
        case .weight: "Tapping it opens the weight log."
        case .custom: "A plain reminder — tick it off when it's done."
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: RivaSpacing.sm) {
            Button {
                Task {
                    isSaving = true
                    let saved = await onSave(draft)
                    isSaving = false
                    guard saved else { return }
                    didSave = true
                    try? await Task.sleep(for: .seconds(1.0))
                    onClose()
                }
            } label: {
                if isSaving {
                    ProgressView().tint(RivaColor.textOnBrand)
                } else {
                    Text(isEditing ? "Save" : "Set to-do")
                }
            }
            .buttonStyle(.rivaPrimary)
            .disabled(!draft.isValid || isSaving)

            if let onDelete {
                Button("Delete to-do") {
                    Task {
                        await onDelete()
                        onClose()
                    }
                }
                .buttonStyle(.rivaDestructive)
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
    }
}

#Preview("Create") {
    Color.clear.sheet(isPresented: .constant(true)) {
        TodoEditorSheet(todo: nil, notificationsDenied: false, onSave: { _ in true }) {}
    }
}

#Preview("Edit") {
    Color.clear.sheet(isPresented: .constant(true)) {
        TodoEditorSheet(
            todo: MockTodoRepository.fixture()[0],
            notificationsDenied: true,
            onSave: { _ in true },
            onDelete: {}
        ) {}
    }
}
