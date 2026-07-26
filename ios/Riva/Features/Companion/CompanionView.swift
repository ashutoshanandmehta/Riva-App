import SwiftUI

/// AI Companion screen — TPC Companion v3 design.
///
/// UI shell only: backend not yet connected. Responses are classified locally
/// by keyword so triage cards render correctly in the interim.
struct CompanionView: View {
    enum Mode { case care, ai }

    @State private var mode: Mode = .ai
    @State private var messages: [CompanionMessage] = [CompanionTriage.greeting]
    @State private var draft = ""
    @State private var isThinking = false
    @State private var scrollID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            modeToggle
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

            flagsLegend
                .padding(.horizontal, 22)
                .padding(.bottom, 10)

            Divider()
                .overlay(TPCColor.surfaceOutline)

            chatArea

            quickChipsRow

            inputArea
        }
        .background(TPCColor.background)
        .contentMargins(.bottom, 0, for: .scrollContent)
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

            Button {
                // Options sheet — wired when care team backend is ready
            } label: {
                Text("⋯")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(TPCColor.textTertiary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
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

    // MARK: Flags legend

    private var flagsLegend: some View {
        HStack(spacing: TPCSpacing.md) {
            Text("FLAGS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TPCColor.textFaint)
                .kerning(0.16)

            flagDot(color: TPCColor.positive, label: "All good")
            flagDot(color: TPCColor.warning, label: "Get checked")
            flagDot(color: TPCColor.danger, label: "Right now")

            Spacer()
        }
    }

    private func flagDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .kerning(0.1)
                .textCase(.uppercase)
        }
    }

    // MARK: Chat area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        messageRow(message)
                    }
                    if isThinking { thinkingIndicator }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: isThinking) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: Message row

    private func messageRow(_ message: CompanionMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
                bubble(message)
                if let triage = message.triage {
                    triageCard(triage)
                }
            }
            .frame(maxWidth: 302, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .bot { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func bubble(_ message: CompanionMessage) -> some View {
        let isUser = message.role == .user
        return Text(message.text)
            .font(TPCFont.body)
            .foregroundStyle(isUser ? TPCColor.textOnInversePrimary : TPCColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                isUser ? TPCColor.surfaceInverse : TPCColor.surface,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 20, bottomLeadingRadius: isUser ? 20 : 6,
                    bottomTrailingRadius: isUser ? 6 : 20, topTrailingRadius: 20
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 20, bottomLeadingRadius: isUser ? 20 : 6,
                    bottomTrailingRadius: isUser ? 6 : 20, topTrailingRadius: 20
                )
                .strokeBorder(
                    isUser ? TPCColor.surfaceInverse : TPCColor.surfaceOutline,
                    lineWidth: 1
                )
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    // MARK: Triage card

    private func triageCard(_ triage: TriageCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Flag header strip
            HStack(spacing: 9) {
                Circle()
                    .fill(triageColor(triage.level))
                    .frame(width: 9, height: 9)
                Text(triage.flagLabel)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(triageLabelColor(triage.level))
                    .kerning(0.16)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(triageBgColor(triage.level))

            // Body
            VStack(alignment: .leading, spacing: 11) {
                Text(triage.actionTitle)
                    .font(TPCFont.sectionTitle)
                    .foregroundStyle(TPCColor.textPrimary)

                Text(triage.actionBody)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    // CTA — wired when care team backend is ready
                } label: {
                    Text(triage.ctaLabel)
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(TPCColor.textOnInversePrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(triageCtaColor(triage.level), in: Capsule())
                }
                .buttonStyle(.plain)

                if let secondary = triage.secondaryLabel {
                    Button {
                        // Secondary CTA
                    } label: {
                        Text(secondary)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(TPCColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(TPCColor.surfaceOutline.opacity(0.18 / 0.10), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(TPCColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .tpcSurfaceOutline(cornerRadius: 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Triage colour helpers

    private func triageColor(_ level: TriageCard.TriageLevel) -> Color {
        switch level {
        case .green: TPCColor.positive
        case .amber: TPCColor.warning
        case .red:   TPCColor.danger
        }
    }

    private func triageLabelColor(_ level: TriageCard.TriageLevel) -> Color {
        switch level {
        case .green: TPCColor.positive
        case .amber: Color(hex: 0x96650F)
        case .red:   TPCColor.danger
        }
    }

    private func triageBgColor(_ level: TriageCard.TriageLevel) -> Color {
        switch level {
        case .green: TPCColor.positive.opacity(0.12)
        case .amber: TPCColor.warning.opacity(0.18)
        case .red:   TPCColor.danger.opacity(0.10)
        }
    }

    private func triageCtaColor(_ level: TriageCard.TriageLevel) -> Color {
        switch level {
        case .green: TPCColor.surfaceInverse
        case .amber: TPCColor.brand
        case .red:   TPCColor.danger
        }
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
                ForEach(CompanionTriage.quickChips, id: \.self) { chip in
                    Button {
                        sendMessage(chip)
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
                TextField("What's going on? Just type it…", text: $draft, axis: .vertical)
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textPrimary)
                    .lineLimit(1...4)
                    .onSubmit { sendMessage(draft) }

                Button {
                    sendMessage(draft)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TPCColor.textOnInversePrimary)
                        .frame(width: 44, height: 44)
                        .background(TPCColor.surfaceInverse, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .background(TPCColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(TPCColor.surfaceOutline, lineWidth: 1))

            Text("Not a diagnosis — anything red goes straight to a clinician")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TPCColor.textFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .padding(.bottom, TPCLayout.tabBarClearance - 12)
    }

    // MARK: Send logic

    private func sendMessage(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        draft = ""
        messages.append(CompanionMessage(role: .user, text: body))
        isThinking = true

        Task {
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                isThinking = false
                messages.append(CompanionTriage.classify(body))
            }
        }
    }
}

#Preview {
    CompanionView()
}
