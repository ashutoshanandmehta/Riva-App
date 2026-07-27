import SwiftUI

/// Wraps the to-do card and its editor sheet, so Home stays a plain list of
/// cards and to-do state never leaks into `AppModel`.
///
/// The view model is injected rather than owned: Home reads the same list for
/// its "Knocked out today" counter, so one fetch serves both and a toggle here
/// moves the counter there.
struct TodoSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    private let viewModel: TodoListViewModel
    @State private var isEditing = false
    @State private var editorTarget: EditorTarget?

    init(viewModel: TodoListViewModel) {
        self.viewModel = viewModel
    }

    /// Identifies which editor is open. A nil `todo` means "Set a to-do".
    private struct EditorTarget: Identifiable {
        let todo: Todo?
        var id: String { todo?.id ?? "new" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
            switch viewModel.state {
            case .loading:
                loadingCard
            case .failed(let message):
                failedCard(message)
            case .loaded:
                card
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.danger)
                    .padding(.horizontal, TPCSpacing.xs)
                    .onTapGesture { viewModel.dismissError() }
            }
        }
        // First load and post-write reloads are driven by the owner (Home), so
        // the shared view model is fetched once per refresh, not twice.
        //
        // The daily reset lands at local midnight, which is invisible to a warm
        // app without this. Reloading also re-arms the notifications for
        // whatever reopened.
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await viewModel.load() }
        }
        .sheet(item: $editorTarget) { target in
            TodoEditorSheet(
                todo: target.todo,
                notificationsDenied: viewModel.notificationsDenied,
                onSave: { draft in await viewModel.save(draft) },
                onDelete: target.todo.map { todo in
                    { await viewModel.delete(todo) }
                },
                onClose: { editorTarget = nil }
            )
        }
    }

    private var card: some View {
        TodoCard(
            groups: viewModel.grouped,
            remainingCount: viewModel.remainingCount,
            isEditing: $isEditing,
            onToggle: { todo in Task { await viewModel.toggle(todo) } },
            onOpen: open,
            onEdit: { todo in editorTarget = EditorTarget(todo: todo) },
            onDelete: { todo in Task { await viewModel.delete(todo) } },
            onCreate: { editorTarget = EditorTarget(todo: nil) }
        )
    }

    /// Food, water, and weight to-dos open the feature that already logs them
    /// — the same routing the snap menu uses.
    private func open(_ todo: Todo) {
        guard let action = todo.category.snapAction else { return }
        appModel.open(snapAction: action)
    }

    // MARK: Loading / error

    private var loadingCard: some View {
        RivaCard {
            HStack(spacing: TPCSpacing.sm) {
                RivaIconChip(systemImage: "checklist")
                Text("To-dos")
                    .font(TPCFont.cardTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Spacer()
                ProgressView().tint(TPCColor.brand)
            }
        }
    }

    private func failedCard(_ message: String) -> some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                Text("To-dos")
                    .font(TPCFont.cardTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text(message)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
                Button("Try again") {
                    Task { await viewModel.load() }
                }
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.brand)
            }
        }
    }
}

#Preview {
    // Home owns the load in the app; the preview stands in for that owner.
    let viewModel = TodoListViewModel(repository: MockTodoRepository())
    ScrollView {
        TodoSection(viewModel: viewModel)
            .padding()
            .task { await viewModel.load() }
    }
    .background(TPCColor.background)
    .environment(AppModel())
}
