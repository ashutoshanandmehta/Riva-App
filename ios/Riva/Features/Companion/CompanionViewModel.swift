import Foundation
import Observation

/// Drives the AI companion conversation: one turn at a time against
/// `/v1/chat`, plus the write gate.
///
/// The thread id is the only thing that persists locally. It is an opaque
/// server UUID rather than a credential, so `UserDefaults` is the right home —
/// the token stays in `KeychainStore`.
@MainActor
@Observable
final class CompanionViewModel {

    private static let threadKey = "companion.threadId"

    private(set) var messages: [CompanionMessage] = [CompanionCopy.greeting]
    private(set) var isThinking = false
    /// Set when a turn failed. The last question is kept in `retryQuery` so the
    /// user can resend it without retyping.
    private(set) var errorMessage: String?
    /// The staged write awaiting the user's answer, if any.
    private(set) var pendingWrite: CompanionWritePreview?
    /// Bumped whenever a turn completed a server-side write. The view observes
    /// it and asks the app to refresh, the same way every other write path does
    /// — the dashboards are mounted for the whole session and re-fetch only when
    /// told to. A counter rather than a flag: two writes in a row are two
    /// signals, and there is nothing to reset.
    private(set) var writeRevision = 0

    var draft = ""

    private let repository: any CompanionRepository
    private let defaults: UserDefaults
    private var threadId: String?
    /// The failed turn, kept whole. The assent token rides along, because a
    /// confirmed write that failed in transit has to be retried *as* a
    /// confirmed write — resending the bare "yes" would only preview again.
    private var failedTurn: (query: String, confirm: String?)?
    private var hasRestored = false

    init(repository: any CompanionRepository, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
        threadId = defaults.string(forKey: Self.threadKey)
    }

    var canSend: Bool {
        !isThinking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Restore

    /// Replays the last conversation on first appear. Fails soft: a thread the
    /// server no longer has, or an unreachable backend, leaves the greeting.
    func restore() async {
        guard !hasRestored, let threadId else { return }
        hasRestored = true
        let replayed = (try? await repository.transcript(threadId: threadId)) ?? []
        // The user can type before a slow replay lands. Their turn is the more
        // recent truth, so a late transcript must not overwrite it.
        //
        // A late transcript also belongs to whatever thread was current when it
        // was requested. If that is no longer the current thread — the user
        // started a new chat mid-replay — it is not this conversation, and the
        // empty-greeting check below would happily let it through.
        guard self.threadId == threadId, !replayed.isEmpty, messages.count <= 1, !isThinking
        else { return }
        messages = replayed
    }

    /// Abandons the current conversation and starts a fresh one. Nothing is
    /// sent: the next turn goes out with no thread id and the server mints the
    /// new thread, so an empty new chat costs no round trip.
    ///
    /// The staged write and the failed turn go with it. A fingerprint previewed
    /// in the old thread authorises nothing in the new one, and retrying a
    /// failed turn must not resurrect the thread the user just left.
    ///
    /// The draft stays. It is the user's own typing and belongs to no thread, so
    /// discarding it would make this button quietly destructive.
    func startNewConversation() {
        guard !isThinking else { return }
        forgetThread()
        messages = [CompanionCopy.greeting]
        pendingWrite = nil
        errorMessage = nil
        failedTurn = nil
    }

    // MARK: Turn

    func send(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isThinking else { return }
        draft = ""
        messages.append(CompanionMessage(role: .user, text: query))
        await turn(query: query, confirm: nil)
    }

    /// Approves the staged write by returning its fingerprint. The query is a
    /// plain "yes" — the token is what authorises the save, not the wording.
    ///
    /// The caller passes the preview its own card is displaying, and it has to
    /// be the pending one. Otherwise a stale card left on screen by a later turn
    /// would submit a fingerprint for values the user is not looking at, which
    /// is exactly the substitution the write gate exists to prevent.
    func confirmPendingWrite(_ preview: CompanionWritePreview) async {
        guard !isThinking, preview == pendingWrite else { return }
        pendingWrite = nil
        clearPreviewCards()
        messages.append(CompanionMessage(role: .user, text: "Yes, save that."))
        await turn(query: "yes", confirm: preview.fingerprint)
    }

    /// Declines it. Nothing is sent: a refusal is the absence of a token, and
    /// the backend has already written nothing.
    func dismissPendingWrite() {
        pendingWrite = nil
        clearPreviewCards()
    }

    func retry() async {
        guard let failed = failedTurn, !isThinking else { return }
        errorMessage = nil
        await turn(query: failed.query, confirm: failed.confirm)
    }

    // MARK: Internals

    private func turn(query: String, confirm: String?) async {
        isThinking = true
        errorMessage = nil
        defer { isThinking = false }

        do {
            let reply = try await send(query: query, confirm: confirm)
            rememberThread(reply.threadId)
            failedTurn = nil
            // Only the newest preview is answerable, so no older card may stay
            // tappable — `confirmPendingWrite` would reject it anyway, and a
            // button that silently does nothing reads as a failed save.
            clearPreviewCards()
            // Signalled before the prose check below: a write that landed still
            // has to reach the dashboards even if the turn came back wordless.
            if reply.didWrite { writeRevision += 1 }
            let text = reply.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // The card hangs off a message, so prose is what makes a preview
            // answerable. No prose (the server always sends some on this path,
            // but still) means dropping the preview rather than stranding an
            // invisible pending write the user can never agree to.
            pendingWrite = text.isEmpty ? nil : reply.writePreview
            guard !text.isEmpty else { return }
            messages.append(
                CompanionMessage(role: .bot, text: text, writePreview: reply.writePreview)
            )
        } catch is CancellationError {
            // View disappeared mid-turn; the server already stored both turns.
        } catch {
            // The question stays on screen as a user bubble, so the error row
            // reads as "this one didn't go through" rather than losing it.
            failedTurn = (query, confirm)
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "The companion couldn't answer. Try again."
        }
    }

    /// One send, with a single recovery: a thread the server will not accept is
    /// forgotten and the turn is repeated as a new conversation. That is the
    /// self-heal for a deleted thread and for an id left behind by whoever was
    /// signed in on this device before — the backend filters by ownership, so a
    /// stale id is a permanent 404 rather than a leak, but it would wedge the
    /// tab forever if the client kept sending it.
    ///
    /// The assent token is deliberately dropped on the retry: its preview lived
    /// in the old thread, so it authorises nothing in the new one and the write
    /// previews again instead of saving unseen.
    private func send(query: String, confirm: String?) async throws -> CompanionReply {
        do {
            return try await repository.send(query: query, threadId: threadId, confirm: confirm)
        } catch CompanionError.threadGone {
            forgetThread()
            return try await repository.send(query: query, threadId: nil, confirm: nil)
        }
    }

    private func rememberThread(_ id: String) {
        guard threadId != id else { return }
        threadId = id
        defaults.set(id, forKey: Self.threadKey)
    }

    private func forgetThread() {
        threadId = nil
        defaults.removeObject(forKey: Self.threadKey)
    }

    /// Drops every card from the transcript, so an already-spent or superseded
    /// fingerprint cannot be tapped.
    private func clearPreviewCards() {
        for index in messages.indices where messages[index].writePreview != nil {
            messages[index].writePreview = nil
        }
    }
}
