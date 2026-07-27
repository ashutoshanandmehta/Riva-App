import Foundation

/// Scripted companion for previews. A message mentioning a weight returns a
/// staged write so the confirmation card can be laid out without a backend.
struct MockCompanionRepository: CompanionRepository {

    private static let threadId = "00000000-0000-0000-0000-000000000001"

    func send(query: String, threadId: String?, confirm: String?) async throws -> CompanionReply {
        try? await Task.sleep(for: .milliseconds(600))

        if confirm != nil {
            return CompanionReply(
                threadId: Self.threadId,
                message: "Saved — 182 lb for today.",
                writePreview: nil,
                didWrite: true
            )
        }
        if query.lowercased().contains("weigh") {
            return CompanionReply(
                threadId: Self.threadId,
                message: "I can put that in for you — just confirm the number below.",
                writePreview: CompanionWritePreview(
                    fingerprint: "preview-fingerprint",
                    willWrite: "Save today's weight as 182 lb."
                ),
                didWrite: false
            )
        }
        return CompanionReply(
            threadId: Self.threadId,
            message: "Your nausea has eased off — a 3 last week down to a 1 yesterday.",
            writePreview: nil,
            didWrite: false
        )
    }

    func transcript(threadId: String) async throws -> [CompanionMessage] { [] }
}
