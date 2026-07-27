import SwiftUI

/// Returning user signing in with an email address and password, with the
/// reset code flow one tap away.
struct EmailLoginView: View {
    @Bindable var model: AuthModel

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: TPCSpacing.lg) {
                        VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                            Text("Sign in")
                                .font(TPCFont.screenTitle)
                                .foregroundStyle(TPCColor.textPrimary)
                            Text("Use the email and password you set up for your account.")
                                .font(TPCFont.body)
                                .foregroundStyle(TPCColor.textSecondary)
                        }

                        TPCTextField(
                            label: "Email",
                            placeholder: "user@example.com",
                            text: $email,
                            keyboard: .emailAddress,
                            contentType: .emailAddress,
                            capitalization: .never,
                            submitLabel: .next
                        )

                        TPCSecureField(
                            label: "Password",
                            placeholder: "Your password",
                            text: $password,
                            submitLabel: .go,
                            onSubmit: signIn
                        )

                        if let notice = model.notice {
                            Text(notice)
                                .font(TPCFont.footnote)
                                .foregroundStyle(TPCColor.danger)
                        }

                        Button {
                            signIn()
                        } label: {
                            if model.isWorking {
                                ProgressView().tint(TPCColor.textOnBrand)
                            } else {
                                Text("Sign in")
                            }
                        }
                        .buttonStyle(.rivaPrimary)
                        .disabled(model.isWorking || !isComplete)
                        // The shared style doesn't dim on `.disabled`.
                        .opacity(isComplete || model.isWorking ? 1 : 0.45)
                        .animation(.easeInOut(duration: 0.15), value: isComplete)

                        Button("Forgot your password?") {
                            model.startPasswordReset()
                        }
                        .font(TPCFont.captionEmphasized)
                        .foregroundStyle(TPCColor.brand)
                        .disabled(model.isWorking)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.top, TPCSpacing.md)
                    .padding(.bottom, TPCSpacing.xl)
                }
            }
        }
    }

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

            Button("New here? Create an account") {
                model.startEmailSignUp()
            }
            .font(TPCFont.captionEmphasized)
            .foregroundStyle(TPCColor.brand)
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.vertical, TPCSpacing.sm)
    }

    private var isComplete: Bool {
        AuthModel.isPlausibleEmail(
            email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ) && !password.isEmpty
    }

    private func signIn() {
        Task { await model.signInWithEmail(email: email, password: password) }
    }
}

#Preview {
    EmailLoginView(model: AuthModel(
        repository: MockAuthRepository(),
        account: MockAccountRepository()
    ))
}
