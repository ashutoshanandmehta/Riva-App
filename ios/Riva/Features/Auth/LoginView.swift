import SwiftUI

/// Returning user sign in: one Google button, nothing else to remember.
struct LoginView: View {
    @Bindable var model: AuthModel

    var body: some View {
        ZStack {
            RivaColor.background.ignoresSafeArea()

            VStack(spacing: RivaSpacing.lg) {
                HStack {
                    Button {
                        model.backToLanding()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(RivaColor.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(RivaColor.fillNeutral, in: Circle())
                    }
                    .accessibilityLabel("Back")
                    Spacer()
                }
                .padding(.horizontal, RivaSpacing.screenMargin)
                .padding(.top, RivaSpacing.sm)

                Spacer()

                VStack(spacing: RivaSpacing.sm) {
                    Text("Riva")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(RivaColor.brand)
                    Text("Welcome back")
                        .font(RivaFont.sectionTitle)
                        .foregroundStyle(RivaColor.textPrimary)
                    Text("Sign in with the Google account you used before, and your data is right where you left it.")
                        .font(RivaFont.body)
                        .foregroundStyle(RivaColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, RivaSpacing.xxl)
                }

                if let notice = model.notice {
                    Text(notice)
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, RivaSpacing.lg)
                }

                Button {
                    Task { await model.continueWithGoogle(fromLogin: true) }
                } label: {
                    if model.isWorking {
                        ProgressView().tint(RivaColor.textOnBrand)
                    } else {
                        Text("Continue with Google")
                    }
                }
                .buttonStyle(.rivaPrimary)
                .disabled(model.isWorking)
                .padding(.horizontal, RivaSpacing.screenMargin)

                Button("New to Riva? Get started") {
                    model.getStarted()
                }
                .font(RivaFont.captionEmphasized)
                .foregroundStyle(RivaColor.brand)

                Spacer()
                Spacer()
            }
        }
    }
}

#Preview {
    LoginView(model: AuthModel(
        repository: MockAuthRepository(),
        account: MockAccountRepository()
    ))
}
