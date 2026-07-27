import SwiftUI

/// Labelled single-line entry: overline caption, filled rounded box, and an
/// optional footnote or error line underneath.
///
/// Matches the field styling the profile form grew locally, promoted here so
/// the auth screens and that form stay identical.
struct TPCTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    /// Quiet helper copy. Suppressed while `problem` is showing.
    var footnote: String?
    /// Validation failure, shown in danger instead of the footnote.
    var problem: String?

    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .return
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        TPCFieldShell(
            label: label,
            footnote: footnote,
            problem: problem,
            isFocused: isFocused
        ) {
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
        }
    }
}

/// The password twin of `TPCTextField`, with a reveal toggle.
///
/// Revealing is deliberate: NIST SP 800-63B recommends letting people see
/// what they typed, because hidden entry drives shorter, simpler passwords.
struct TPCSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var footnote: String?
    var problem: String?

    var contentType: UITextContentType? = .password
    var submitLabel: SubmitLabel = .return
    var onSubmit: (() -> Void)?

    @State private var isRevealed = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case secure, plain }

    var body: some View {
        TPCFieldShell(
            label: label,
            footnote: footnote,
            problem: problem,
            isFocused: focus != nil
        ) {
            HStack(spacing: TPCSpacing.xs) {
                // Two fields rather than one, because toggling `SecureField`'s
                // own visibility mid-edit drops the text on iOS.
                if isRevealed {
                    TextField(placeholder, text: $text)
                        .focused($focus, equals: .plain)
                } else {
                    SecureField(placeholder, text: $text)
                        .focused($focus, equals: .secure)
                }

                Button {
                    let wasFocused = focus != nil
                    isRevealed.toggle()
                    if wasFocused { focus = isRevealed ? .plain : .secure }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TPCColor.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
        }
    }
}

/// Shared chrome for the two field types: label, box, focus ring, footer.
private struct TPCFieldShell<Content: View>: View {
    let label: String
    let footnote: String?
    let problem: String?
    let isFocused: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
            Text(label)
                .rivaOverline()

            content
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textPrimary)
                .tint(TPCColor.brand)
                .padding(.horizontal, TPCSpacing.md)
                .padding(.vertical, 12)
                .background(
                    TPCColor.fillNeutral,
                    in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )

            if let problem {
                Text(problem)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.danger)
            } else if let footnote {
                Text(footnote)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textTertiary)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: problem)
    }

    private var borderColor: Color {
        if problem != nil { return TPCColor.danger.opacity(0.55) }
        return isFocused ? TPCColor.brand.opacity(0.55) : .clear
    }

    private var borderWidth: CGFloat {
        problem != nil || isFocused ? 1.5 : 0
    }
}

#Preview {
    @Previewable @State var email = ""
    @Previewable @State var password = "hunter2"

    VStack(spacing: TPCSpacing.lg) {
        TPCTextField(
            label: "Email",
            placeholder: "user@example.com",
            text: $email,
            footnote: "We'll send a six digit code here.",
            keyboard: .emailAddress,
            contentType: .emailAddress,
            capitalization: .never
        )
        TPCSecureField(
            label: "Password",
            placeholder: "At least 8 characters",
            text: $password,
            problem: "That's one of the most common passwords. Pick something else."
        )
    }
    .padding(TPCSpacing.screenMargin)
    .background(TPCColor.background)
}
