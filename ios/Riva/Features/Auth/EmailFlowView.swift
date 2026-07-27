import SwiftUI

/// The email wizard: address, then the six digit code, then the password.
///
/// One view serves both journeys — creating an account and resetting a
/// password — because the steps are identical; only the copy and where the
/// last step lands differ. `AuthModel` owns which step is showing.
struct EmailFlowView: View {
    @Bindable var model: AuthModel
    let flow: AuthModel.EmailFlow

    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: TPCSpacing.lg) {
                        switch model.emailStep {
                        case .address: addressStep
                        case .code: codeStep
                        case .password: passwordStep
                        }
                    }
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.top, TPCSpacing.md)
                    .padding(.bottom, TPCSpacing.xl)
                }
            }
        }
        // Never carry a typed password across steps or flows.
        .onChange(of: model.emailStep) { _, _ in
            password = ""
            confirmation = ""
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Button {
                Task { await model.backFromEmail() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TPCColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(TPCColor.fillNeutral, in: Circle())
            }
            .accessibilityLabel("Back")
            .disabled(model.isWorking)

            Spacer()
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.vertical, TPCSpacing.sm)
    }

    private func title(_ text: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
            Text(text)
                .font(TPCFont.screenTitle)
                .foregroundStyle(TPCColor.textPrimary)
            Text(subtitle)
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textSecondary)
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let notice = model.notice {
            Text(notice)
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `TPCPrimaryButtonStyle` doesn't dim on `.disabled`, and these steps gate
    /// the button on validation — so fade it here rather than change the shared
    /// style out from under every other screen.
    private func primary(_ label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if model.isWorking {
                ProgressView().tint(TPCColor.textOnBrand)
            } else {
                Text(label)
            }
        }
        .buttonStyle(.rivaPrimary)
        .disabled(model.isWorking || !isEnabled)
        .opacity(isEnabled || model.isWorking ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
    }

    // MARK: Step one — address

    private var addressStep: some View {
        Group {
            title(
                flow.title,
                flow == .signUp
                    ? "Enter your email and we'll send you a six digit code to confirm it."
                    : "Enter the email on your account and we'll send you a six digit code."
            )

            TPCTextField(
                label: "Email",
                placeholder: "user@example.com",
                text: $email,
                keyboard: .emailAddress,
                contentType: .emailAddress,
                capitalization: .never,
                submitLabel: .send,
                onSubmit: sendCode
            )

            notice
            primary("Send code", isEnabled: AuthModel.isPlausibleEmail(normalizedEmail), action: sendCode)
        }
    }

    // MARK: Step two — code

    private var codeStep: some View {
        Group {
            title(
                "Check your email",
                // Expiry must match `mailer_otp_exp` in
                // backend/scripts/configure_supabase_auth.py.
                "We sent a \(AuthModel.codeLength) digit code to \(model.pendingEmail). It expires in 15 minutes."
            )

            TPCTextField(
                label: "Verification code",
                placeholder: String(repeating: "0", count: AuthModel.codeLength),
                text: $code,
                keyboard: .numberPad,
                // Lets iOS offer the code straight from the Mail notification.
                contentType: .oneTimeCode,
                capitalization: .never,
                onSubmit: verifyCode
            )
            .onChange(of: code) { _, new in
                let digits = new.filter(\.isNumber)
                code = String(digits.prefix(AuthModel.codeLength))
                // Autofill drops all six in at once; don't make them tap.
                if code.count == AuthModel.codeLength, !model.isWorking { verifyCode() }
            }

            notice
            primary(
                "Verify",
                isEnabled: code.count == AuthModel.codeLength,
                action: verifyCode
            )

            Button("Send a new code") {
                Task { await model.resendCode() }
            }
            .font(TPCFont.captionEmphasized)
            .foregroundStyle(TPCColor.brand)
            .disabled(model.isWorking)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Step three — password

    private var passwordStep: some View {
        Group {
            title(
                flow == .signUp ? "Choose a password" : "Set a new password",
                "At least \(PasswordPolicy.minimumLength) characters. Avoid anything you'd guess first."
            )

            TPCSecureField(
                label: "Password",
                placeholder: "At least \(PasswordPolicy.minimumLength) characters",
                text: $password,
                // Guidance, not scolding: this reads as a hint while typing,
                // and the real block is the disabled button below.
                footnote: assessment.problem,
                contentType: .newPassword
            )

            if !password.isEmpty {
                PasswordStrengthMeter(strength: assessment.strength)
            }

            TPCSecureField(
                label: "Confirm password",
                placeholder: "Type it again",
                text: $confirmation,
                problem: mismatch ? "Those two passwords don't match." : nil,
                contentType: .newPassword,
                submitLabel: .done,
                onSubmit: savePassword
            )

            notice
            primary(
                flow == .signUp ? "Create account" : "Save new password",
                isEnabled: assessment.isAcceptable && !confirmation.isEmpty && !mismatch,
                action: savePassword
            )
        }
    }

    // MARK: Derived state

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var assessment: PasswordPolicy.Assessment {
        PasswordPolicy.assess(password, email: model.pendingEmail)
    }

    private var mismatch: Bool {
        !confirmation.isEmpty && password != confirmation
    }

    // MARK: Actions

    private func sendCode() {
        Task { await model.submitEmail(email) }
    }

    private func verifyCode() {
        Task { await model.submitCode(code) }
    }

    private func savePassword() {
        Task { await model.submitPassword(password, confirmation: confirmation) }
    }
}

/// Bar + word for how good the typed password is.
private struct PasswordStrengthMeter: View {
    let strength: PasswordPolicy.Strength

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(TPCColor.fillNeutral)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * strength.fraction)
                }
            }
            .frame(height: 5)

            Text(strength.label)
                .font(TPCFont.caption)
                .foregroundStyle(color)
        }
        .animation(.easeInOut(duration: 0.2), value: strength)
        .accessibilityElement()
        .accessibilityLabel("Password strength: \(strength.label)")
    }

    private var color: Color {
        switch strength {
        case .unacceptable: TPCColor.danger
        case .weak: TPCColor.danger.opacity(0.75)
        case .fair: TPCColor.warning
        case .strong: TPCColor.positive
        }
    }
}

#Preview("Address") {
    EmailFlowView(
        model: AuthModel(repository: MockAuthRepository(), account: MockAccountRepository()),
        flow: .signUp
    )
}
