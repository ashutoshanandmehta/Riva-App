import Foundation

/// To-dos the user sets on the Home card. Server-authoritative like every
/// other Riva resource: the app holds no local copy, and done state is
/// resolved by the backend against the profile timezone.
protocol TodoRepository: Sendable {
    /// Open to-dos, ordered by reminder time.
    func todos() async throws -> [Todo]

    /// Creates the to-do when `draft.id` is nil, else edits that one.
    func save(_ draft: TodoDraft) async throws -> Todo

    func setDone(id: String, done: Bool) async throws -> Todo

    func delete(id: String) async throws
}
