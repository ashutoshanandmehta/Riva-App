import Foundation
import Observation

/// Drives the Home to-do card: loads the list, applies each mutation
/// optimistically, and keeps the local notifications in step with whatever
/// the server last confirmed.
@MainActor
@Observable
final class TodoListViewModel {

    enum State: Equatable {
        case loading
        case loaded([Todo])
        case failed(message: String)
    }

    private(set) var state: State = .loading
    /// Non-nil while a mutation failed and the message hasn't been dismissed.
    private(set) var errorMessage: String?
    /// True once we know the user has notifications turned off, so the editor
    /// can say so instead of silently scheduling nothing.
    private(set) var notificationsDenied = false

    private let repository: any TodoRepository

    init(repository: any TodoRepository) {
        self.repository = repository
    }

    var todos: [Todo] {
        if case .loaded(let todos) = state { return todos }
        return []
    }

    /// Open to-dos grouped for the card, in category order, empty groups
    /// dropped. The server already sorted each list by reminder time.
    var grouped: [(category: TodoCategory, todos: [Todo])] {
        TodoCategory.allCases.compactMap { category in
            let matching = todos.filter { $0.category == category }
            return matching.isEmpty ? nil : (category, matching)
        }
    }

    var remainingCount: Int {
        todos.count { !$0.isDone }
    }

    /// Ticked off today. `isDone` is resolved server-side against the profile
    /// timezone, so this needs no day math — it also backs Home's
    /// "Habits completed" counter.
    var completedCount: Int {
        todos.count { $0.isDone }
    }

    // MARK: Loading

    func load() async {
        // Keep already-loaded content on screen during a refresh.
        if case .loaded = state {} else { state = .loading }
        // The editor reads this to explain why a reminder won't arrive, so it
        // has to be known before the first save, not after it.
        notificationsDenied = await TodoNotificationScheduler.isDenied()
        do {
            let todos = try await repository.todos()
            state = .loaded(todos)
            await TodoNotificationScheduler.reconcile(todos)
        } catch {
            // The repository funnels every transport failure, cancellation
            // included, into ScanServiceError — so check the task, not the
            // error type, before painting a failure the user can't act on.
            guard !Task.isCancelled else { return }
            state = .failed(message: "Couldn't load your to-dos. Pull to retry.")
        }
    }

    // MARK: Mutations

    /// Creates or edits, then re-arms the notifications. Asking for permission
    /// here rather than at launch keeps the prompt tied to a deliberate action.
    func save(_ draft: TodoDraft) async -> Bool {
        errorMessage = nil
        notificationsDenied = await TodoNotificationScheduler.requestAuthorization() == false
        do {
            let saved = try await repository.save(draft)
            replace(saved)
            await reconcile()
            return true
        } catch {
            errorMessage = Self.message(for: error, fallback: "Couldn't save that to-do.")
            return false
        }
    }

    func toggle(_ todo: Todo) async {
        errorMessage = nil
        // Flip locally first so the checkmark responds immediately.
        var optimistic = todo
        optimistic.isDone.toggle()
        replace(optimistic)
        do {
            replace(try await repository.setDone(id: todo.id, done: optimistic.isDone))
            await reconcile()
        } catch {
            replace(todo)  // Server said no; put it back.
            errorMessage = Self.message(for: error, fallback: "Couldn't update that to-do.")
        }
    }

    func delete(_ todo: Todo) async {
        errorMessage = nil
        guard case .loaded(let previous) = state else { return }
        remove(todo.id)
        do {
            // Idempotent: an already-deleted to-do is a success, not a reason
            // to put the row back (see APITodoRepository.delete).
            try await repository.delete(id: todo.id)
            await reconcile()
        } catch {
            state = .loaded(previous)
            errorMessage = Self.message(for: error, fallback: "Couldn't delete that to-do.")
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: Local state

    private func replace(_ todo: Todo) {
        // Never invent a loaded state from .loading/.failed: that would strip
        // the retry affordance and show a card built from one row.
        guard case .loaded(var todos) = state else { return }
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = todo
        } else {
            todos.append(todo)
        }
        // Mirror list_todos' ordering after an edit moved the time. Swift's
        // sort is not stable, so id breaks ties rather than letting same-time
        // rows shuffle past each other on every toggle.
        state = .loaded(todos.sorted {
            ($0.remindHour, $0.remindMinute, $0.id) < ($1.remindHour, $1.remindMinute, $1.id)
        })
    }

    private func remove(_ id: String) {
        guard case .loaded(var todos) = state else { return }
        todos.removeAll { $0.id == id }
        state = .loaded(todos)
    }

    private func reconcile() async {
        await TodoNotificationScheduler.reconcile(todos)
    }

    private static func message(for error: Error, fallback: String) -> String {
        if case ScanServiceError.service(let detail) = error { return detail }
        if case ScanServiceError.signInRequired = error { return "Sign in to keep your to-dos." }
        return fallback
    }
}
