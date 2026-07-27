import Foundation

/// The AI companion: one question in, a grounded answer out, plus the write
/// gate that lets the user save something from the conversation.
///
/// The subject of every call is the signed-in user, established server-side
/// from the bearer token alone. No method takes a user or patient id, and no
/// implementation may put one on the wire — see `APICompanionRepository`.
protocol CompanionRepository: Sendable {

    /// One turn. `threadId` is nil for the first message of a conversation;
    /// the reply carries the id to send back on every message after it.
    ///
    /// `confirm` is the fingerprint from a `CompanionWritePreview` the user has
    /// just approved. It travels on the request because the model must not be
    /// able to manufacture the user's agreement — see
    /// `backend/app/chat/confirm.py`.
    func send(query: String, threadId: String?, confirm: String?) async throws -> CompanionReply

    /// Replays a stored conversation, oldest turn first. A thread that no
    /// longer exists returns an empty transcript rather than throwing.
    func transcript(threadId: String) async throws -> [CompanionMessage]
}

/// Failures specific to the companion, alongside the shared `ScanServiceError`.
enum CompanionError: Error {
    /// The stored thread id is not (or is no longer) this user's — deleted, or
    /// left behind by whoever was signed in before. The caller must forget it
    /// and start a fresh conversation; retrying with it never recovers.
    case threadGone
}

// MARK: - Reply

/// One `POST /v1/chat` response.
struct CompanionReply {
    /// Server-minted; persist it opaquely and echo it back. Never parsed or
    /// constructed client-side.
    let threadId: String
    /// The grounded answer. Nil only on the command path, which this client
    /// does not use.
    let message: String?
    /// The write the user still has to approve, if the turn produced one.
    let writePreview: CompanionWritePreview?
    /// The turn completed a server-side write, so anything showing that data is
    /// now stale. Read off the tool result rather than inferred from having sent
    /// an assent token: a command turn writes without the client gating it.
    let didWrite: Bool
}

// MARK: - Write gate

/// A write the backend has staged but not performed, naming exactly what would
/// be saved. Approving it means sending `fingerprint` back on the next request;
/// a refusal is simply never sending it.
struct CompanionWritePreview: Equatable {
    /// Single-use. Once spent on a completed write, replaying it previews again.
    let fingerprint: String
    /// The server's own sentence describing the write, shown verbatim — the
    /// client must not paraphrase what the user is agreeing to.
    let willWrite: String
}
