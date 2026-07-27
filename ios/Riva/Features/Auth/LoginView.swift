import SwiftUI

/// Returning user sign in: Google or Apple, nothing else to remember.
struct LoginView: View {
    @Bindable var model: AuthModel

    var body: some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()

            VStack(spacing: TPCSpacing.lg) {
                HStack {
                    Button {
                        model.backToLanding()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TPCColor.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(TPCColor.fillNeutral, in: Circle())
                    }
                    .accessibilityLabel("Back")
                    Spacer()
                }
                .padding(.horizontal, TPCSpacing.screenMargin)
                .padding(.top, TPCSpacing.sm)

                Spacer()

                VStack(spacing: TPCSpacing.sm) {
                    TPCSeal(size: 72)
                    Text("Welcome back")
                        .font(TPCFont.sectionTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text("Sign in with the account you used before, and your data is right where you left it.")
                        .font(TPCFont.body)
                        .foregroundStyle(TPCColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TPCSpacing.xxl)
                }

                if let notice = model.notice {
                    Text(notice)
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TPCSpacing.lg)
                }

                Button {
                    Task { await model.continueWithGoogle(fromLogin: true) }
                } label: {
                    if model.isWorking {
                        ProgressView().tint(TPCColor.textOnBrand)
                    } else {
                        Text("Continue with Google")
                    }
                }
                .buttonStyle(.rivaPrimary)
                .disabled(model.isWorking)
                .padding(.horizontal, TPCSpacing.screenMargin)

                AppleSignInButton(model: model, fromLogin: true)
                    .padding(.horizontal, TPCSpacing.screenMargin)

                Button("New to TPC? Get started") {
                    model.getStarted()
                }
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.brand)

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
