import SwiftUI

/// Home's to-do card: every open to-do as one list, clubbed under its
/// category. Ticking the circle marks it done; tapping the row opens the Snap
/// feature that logs it (food, water, weight). "Edit" reveals a pencil and a
/// trash on each row.
struct TodoCard: View {
    let groups: [(category: TodoCategory, todos: [Todo])]
    let remainingCount: Int
    @Binding var isEditing: Bool
    let onToggle: (Todo) -> Void
    /// Called for any row; a custom to-do has no feature to open, so the row
    /// is disabled and this never fires for one.
    let onOpen: (Todo) -> Void
    let onEdit: (Todo) -> Void
    let onDelete: (Todo) -> Void
    let onCreate: () -> Void

    var body: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                header
                if groups.isEmpty {
                    emptyState
                } else {
                    list
                }
                footer
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: RivaSpacing.xs) {
            RivaIconChip(systemImage: "checklist")
            Text("To-dos")
                .font(RivaFont.cardTitle)
                .foregroundStyle(RivaColor.textPrimary)
            Spacer()
            if remainingCount > 0 {
                RivaBadge(text: "\(remainingCount) left")
            } else if !groups.isEmpty {
                RivaBadge(text: "All done", style: .brand)
            }
        }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.sm) {
            ForEach(groups, id: \.category) { group in
                VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                    Text(group.category.title)
                        .rivaOverline()
                    ForEach(group.todos) { todo in
                        row(todo)
                    }
                }
            }
        }
    }

    private func row(_ todo: Todo) -> some View {
        HStack(spacing: RivaSpacing.sm) {
            Button {
                onToggle(todo)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(todo.isDone ? RivaColor.brand : RivaColor.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark \(todo.title) not done" : "Mark \(todo.title) done")

            Button {
                onOpen(todo)
            } label: {
                HStack(spacing: RivaSpacing.xs) {
                    Text(todo.title)
                        .font(RivaFont.body)
                        .foregroundStyle(todo.isDone ? RivaColor.textTertiary : RivaColor.textPrimary)
                        .strikethrough(todo.isDone, color: RivaColor.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: RivaSpacing.xs)
                    Text(todo.scheduleText)
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(todo.category.snapAction == nil)

            if isEditing {
                Button(action: { onEdit(todo) }) {
                    Image(systemName: "pencil")
                        .foregroundStyle(RivaColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(todo.title)")

                Button(action: { onDelete(todo) }) {
                    Image(systemName: "trash")
                        .foregroundStyle(RivaColor.danger)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(todo.title)")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Empty state and footer

    private var emptyState: some View {
        Text("No to-dos yet. Set one and Riva will nudge you at the right time.")
            .font(RivaFont.footnote)
            .foregroundStyle(RivaColor.textSecondary)
            .padding(.vertical, RivaSpacing.xs)
    }

    private var footer: some View {
        HStack(spacing: RivaSpacing.sm) {
            Button("Set a to-do", action: onCreate)
                .buttonStyle(.rivaPrimary)
            if !groups.isEmpty {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation(.easeInOut(duration: 0.2)) { isEditing.toggle() }
                }
                .font(RivaFont.captionEmphasized)
                .foregroundStyle(RivaColor.brand)
                .padding(.horizontal, RivaSpacing.sm)
            }
        }
    }
}

#Preview {
    @Previewable @State var isEditing = false
    let todos = MockTodoRepository.fixture()
    let groups = TodoCategory.allCases.compactMap { category -> (TodoCategory, [Todo])? in
        let matching = todos.filter { $0.category == category }
        return matching.isEmpty ? nil : (category, matching)
    }
    return ScrollView {
        TodoCard(
            groups: groups,
            remainingCount: todos.count { !$0.isDone },
            isEditing: $isEditing,
            onToggle: { _ in },
            onOpen: { _ in },
            onEdit: { _ in },
            onDelete: { _ in },
            onCreate: {}
        )
        .padding()
    }
    .background(RivaColor.background)
}
