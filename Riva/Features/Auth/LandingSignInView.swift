import SwiftUI

/// The one place the user ever signs in: shown at launch when no session
/// exists. Email in, six digit code back, done.
///
/// Provisional layout: the branded landing design will replace the header
/// here; the card and flow underneath stay.
struct LandingSignInView: View {
    @Bindable var model: AuthModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case code
    }

    var body: some View {
        ZStack {
            RivaColor.background.ignoresSafeArea()

            VStack(spacing: RivaSpacing.xl) {
                Spacer()

                VStack(spacing: RivaSpacing.xs) {
                    Text("Riva")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(RivaColor.brand)
                    Text("Your companion through every week of treatment")
                        .font(RivaFont.body)
                        .foregroundStyle(RivaColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, RivaSpacing.xxl)
                }

                signInCard

                Spacer()
                Spacer()
            }
        }
    }

    private var signInCard: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                if model.step == .email {
                    Text("Sign in with your email. We will send a six digit code, no password needed.")
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textSecondary)

                    field {
                        TextField("Email address", text: $model.email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .onSubmit { Task { await model.sendCode() } }
                    }

                    Button {
                        Task { await model.sendCode() }
                    } label: {
                        workingLabel("Send code")
                    }
                    .buttonStyle(.rivaPrimary)
                    .disabled(model.isWorking)
                } else {
                    field {
                        TextField("Six digit code", text: $model.code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .code)
                            .onSubmit { Task { await model.verifyCode() } }
                    }

                    Button {
                        Task { await model.verifyCode() }
                    } label: {
                        workingLabel("Verify and continue")
                    }
                    .buttonStyle(.rivaPrimary)
                    .disabled(model.isWorking)

                    Button("Use a different email") { model.changeEmail() }
                        .font(RivaFont.captionEmphasized)
                        .foregroundStyle(RivaColor.brand)
                        .frame(maxWidth: .infinity)
                }

                if let notice = model.notice {
                    Text(notice)
                        .font(RivaFont.footnote)
                        .foregroundStyle(noticeColor(notice))
                }
            }
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .onAppear {
            focusedField = model.step == .email ? .email : .code
        }
        .onChange(of: model.step) {
            focusedField = model.step == .email ? .email : .code
        }
    }

    private func field(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(RivaFont.body)
            .foregroundStyle(RivaColor.textPrimary)
            .padding(.horizontal, RivaSpacing.md)
            .padding(.vertical, 13)
            .background(
                RivaColor.fillNeutral,
                in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
            )
    }

    private func workingLabel(_ title: String) -> some View {
        Group {
            if model.isWorking {
                ProgressView().tint(RivaColor.textOnBrand)
            } else {
                Text(title)
            }
        }
    }

    private func noticeColor(_ notice: String) -> Color {
        notice.hasPrefix("We emailed") ? RivaColor.textSecondary : RivaColor.danger
    }
}

#Preview {
    LandingSignInView(model: AuthModel(repository: MockAuthRepository()))
}
