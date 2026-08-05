import SwiftUI

/// AI Companion screen — TPC Companion v3 design.
///
/// Backed by `/v1/chat`: the answer, and any write it stages, come from the
/// server. Nothing clinical is decided here — the view renders the reply and
/// the confirmation card, and never classifies or paraphrases it.
struct CompanionView: View {
    enum Mode { case care, ai }

    @Environment(AppModel.self) private var appModel

    @State private var mode: Mode = .ai
    @State private var model: CompanionViewModel
    @FocusState private var isInputFocused: Bool

    init(repository: any CompanionRepository) {
        _model = State(initialValue: CompanionViewModel(repository: repository))
    }

    var body: some View {
        VStack(spacing: 0) {
            modeToggle
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

            Divider()
                .overlay(TPCColor.surfaceOutline)

            if mode == .care {
                CareTeamView()
            } else {
                chatArea

                quickChipsRow

                inputArea
            }
        }
        .background(TPCColor.background)
        .contentMargins(.bottom, 0, for: .scrollContent)
        .task { await model.restore() }
        // A chat write lands on the server, so the mounted dashboards are stale
        // until they are told. Same signal the quick-log and scan paths send.
        .onChange(of: model.writeRevision) { appModel.refreshDashboards() }
    }

    // MARK: Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                toggleButton(label: "♥  Care team", selected: mode == .care) { mode = .care }
                toggleButton(label: "✦  AI companion", selected: mode == .ai) { mode = .ai }
            }
            .padding(4)
            .background(TPCColor.fillNeutral, in: Capsule())
            .overlay(Capsule().strokeBorder(TPCColor.surfaceOutline, lineWidth: 1))

            Spacer()

            if mode == .ai {
                Menu {
                    Button("New chat", systemImage: "square.and.pencil") {
                        model.startNewConversation()
                    }
                    .disabled(model.isThinking)
                } label: {
                    Text("⋯")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(TPCColor.textTertiary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Conversation options")
            }
        }
    }

    private func toggleButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(selected ? TPCColor.textOnInversePrimary : TPCColor.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(selected ? TPCColor.surfaceInverse : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Chat area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
                        messageRow(message)
                    }
                    if model.isThinking { thinkingIndicator }
                    if let error = model.errorMessage { errorRow(error) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: model.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.isThinking) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            // Care team unmounts this ScrollView; coming back would otherwise
            // reopen at the top of the transcript.
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            // Tapping or dragging the transcript puts the keyboard away —
            // `.vertical` text fields have no return key to submit with.
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
        }
    }

    // MARK: Message row

    private func messageRow(_ message: CompanionMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
                CompanionBubble(text: message.text, isUser: message.role == .user)
                if let preview = message.writePreview {
                    confirmCard(preview)
                }
            }
            .frame(maxWidth: 302, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .bot { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    // MARK: Write confirmation

    /// The write gate. Nothing has been saved yet: `willWrite` is the server's
    /// own sentence, shown verbatim, and Confirm returns the fingerprint that
    /// authorises exactly those values. "Not now" sends nothing at all.
    private func confirmCard(_ preview: CompanionWritePreview) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Save this?")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(TPCColor.textFaint)
                .kerning(0.16)
                .textCase(.uppercase)

            Text(preview.willWrite)
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    // The displayed preview, not "whatever is pending" — the
                    // user is agreeing to the values on this card.
                    Task { await model.confirmPendingWrite(preview) }
                } label: {
                    Text("Confirm")
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(TPCColor.textOnInversePrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(TPCColor.surfaceInverse, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.dismissPendingWrite()
                } label: {
                    Text("Not now")
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(TPCColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(Capsule().strokeBorder(TPCColor.surfaceOutline, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            .disabled(model.isThinking)
        }
        .padding(16)
        .background(TPCColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .tpcSurfaceOutline(cornerRadius: 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Error row

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Text(message)
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.danger)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await model.retry() }
            } label: {
                Text("Retry")
                    .font(TPCFont.captionEmphasized)
                    .foregroundStyle(TPCColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .overlay(Capsule().strokeBorder(TPCColor.surfaceOutline, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    // MARK: Thinking indicator

    private var thinkingIndicator: some View {
        HStack(spacing: 7) {
            ForEach([1.0, 0.5, 0.25], id: \.self) { opacity in
                Circle()
                    .fill(TPCColor.brand.opacity(opacity))
                    .frame(width: 7, height: 7)
            }
            Text("Having a look…")
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textTertiary)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    // MARK: Quick chips

    private var quickChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CompanionCopy.quickChips, id: \.self) { chip in
                    Button {
                        send(chip)
                    } label: {
                        Text(chip)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(TPCColor.textPrimary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background(TPCColor.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(TPCColor.surfaceOutline.opacity(1.2), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 4)
    }

    // MARK: Input bar

    private var inputArea: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                TextField("What's going on? Just type it…", text: $model.draft, axis: .vertical)
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textPrimary)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit { send() }

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TPCColor.textOnInversePrimary)
                        .frame(width: 44, height: 44)
                        .background(TPCColor.surfaceInverse, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .opacity(model.canSend ? 1 : 0.4)
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .background(TPCColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(TPCColor.surfaceOutline, lineWidth: 1))

            // No routing is promised here: nothing in the app reaches a
            // clinician yet, so the line says what to do, not what we'll do.
            Text("Not a diagnosis — for anything urgent, contact your clinician")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TPCColor.textFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .padding(.bottom, TPCLayout.tabBarClearance - 12)
    }

    // MARK: Send

    /// Sends `text`, or the draft when called from the input bar. Focus is
    /// released either way so the reply isn't hidden behind the keyboard.
    private func send(_ text: String? = nil) {
        let message = text ?? model.draft
        isInputFocused = false
        Task { await model.send(message) }
    }
}

#Preview {
    CompanionView(repository: MockCompanionRepository())
        .environment(AppModel())
}
