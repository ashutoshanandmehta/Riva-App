import Foundation

/// In-memory to-dos for SwiftUI previews. Mutations are applied to a local
/// store so the card behaves like the real thing without a backend.
final class MockTodoRepository: TodoRepository, @unchecked Sendable {

    private var store: [Todo]

    init(todos: [Todo] = MockTodoRepository.fixture()) {
        store = todos
    }

    func todos() async throws -> [Todo] {
        try await Task.sleep(for: .milliseconds(150))
        return store.sorted { ($0.remindHour, $0.remindMinute) < ($1.remindHour, $1.remindMinute) }
    }

    func save(_ draft: TodoDraft) async throws -> Todo {
        let calendar = Calendar.current
        let todo = Todo(
            id: draft.id ?? UUID().uuidString,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category,
            repeatRule: draft.repeatRule,
            remindHour: calendar.component(.hour, from: draft.time),
            remindMinute: calendar.component(.minute, from: draft.time),
            dueDate: draft.repeatRule == .once ? AccountDates.dayString(draft.day) : nil,
            isDone: store.first { $0.id == draft.id }?.isDone ?? false
        )
        if let index = store.firstIndex(where: { $0.id == todo.id }) {
            store[index] = todo
        } else {
            store.append(todo)
        }
        return todo
    }

    func setDone(id: String, done: Bool) async throws -> Todo {
        guard let index = store.firstIndex(where: { $0.id == id }) else {
            throw ScanServiceError.service("That to-do no longer exists.")
        }
        store[index].isDone = done
        return store[index]
    }

    func delete(id: String) async throws {
        store.removeAll { $0.id == id }
    }

    // MARK: - Fixture

    static func fixture() -> [Todo] {
        [
            Todo(
                id: "todo-weigh",
                title: "Morning weigh-in",
                category: .weight,
                repeatRule: .daily,
                remindHour: 7,
                remindMinute: 0,
                dueDate: nil,
                isDone: true
            ),
            Todo(
                id: "todo-breakfast",
                title: "Log breakfast",
                category: .food,
                repeatRule: .daily,
                remindHour: 8,
                remindMinute: 30,
                dueDate: nil,
                isDone: false
            ),
            Todo(
                id: "todo-water",
                title: "Drink 8 glasses",
                category: .water,
                repeatRule: .daily,
                remindHour: 12,
                remindMinute: 0,
                dueDate: nil,
                isDone: false
            ),
            Todo(
                id: "todo-dinner",
                title: "Log dinner",
                category: .food,
                repeatRule: .daily,
                remindHour: 19,
                remindMinute: 0,
                dueDate: nil,
                isDone: false
            ),
            Todo(
                id: "todo-refill",
                title: "Order pen refill",
                category: .custom,
                repeatRule: .once,
                remindHour: 20,
                remindMinute: 15,
                dueDate: AccountDates.dayString(Date.now.addingTimeInterval(86_400)),
                isDone: false
            ),
        ]
    }
}
