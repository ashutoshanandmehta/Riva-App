import SwiftUI

/// Onboarding: pick health goals, then create the account with Google.
/// Returning users jump to login from the link up top.
struct GoalsStepView: View {
    @Bindable var model: AuthModel

    var body: some View {
        ZStack {
            TPCColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: TPCSpacing.md) {
                        VStack(alignment: .leading, spacing: TPCSpacing.xxs) {
                            Text("What brings you to The Peptide Company?")
                                .font(TPCFont.screenTitle)
                                .foregroundStyle(TPCColor.textPrimary)
                            Text("Select all that apply to help us personalize your journey.")
                                .font(TPCFont.body)
                                .foregroundStyle(TPCColor.textSecondary)
                        }

                        ForEach(OnboardingGoal.allCases) { goal in
                            goalCard(goal)
                        }
                    }
                    .padding(.horizontal, TPCSpacing.screenMargin)
                    .padding(.bottom, TPCSpacing.xl)
                }

                footer
            }
        }
    }

    private var header: some View {
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

            Button("Already a user? Log in") {
                model.showLogin()
            }
            .font(TPCFont.captionEmphasized)
            .foregroundStyle(TPCColor.brand)
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.vertical, TPCSpacing.sm)
    }

    private func goalCard(_ goal: OnboardingGoal) -> some View {
        let isSelected = model.selectedGoals.contains(goal)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                model.toggle(goal)
            }
        } label: {
            HStack(spacing: TPCSpacing.md) {
                Image(systemName: goal.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? TPCColor.textOnBrand : TPCColor.brand)
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected ? TPCColor.brand : TPCColor.brandWash,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(TPCFont.cardTitle)
                        .foregroundStyle(TPCColor.textPrimary)
                    Text(goal.subtitle)
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                }
                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? TPCColor.brand : TPCColor.textTertiary)
            }
            .padding(TPCSpacing.md)
            .background(
                TPCColor.surface,
                in: RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TPCRadius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? TPCColor.brand.opacity(0.5) : TPCColor.surfaceOutline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: TPCSpacing.xs) {
            if let notice = model.notice {
                Text(notice)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TPCSpacing.lg)
            }
            Button {
                Task { await model.continueWithGoogle(fromLogin: false) }
            } label: {
                if model.isWorking {
                    ProgressView().tint(TPCColor.textOnBrand)
                } else {
                    Text("Create account with Google")
                }
            }
            .buttonStyle(.rivaPrimary)
            .disabled(model.isWorking)
            .padding(.horizontal, TPCSpacing.screenMargin)

            Text("Your goals sync to your account after sign in.")
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textTertiary)
        }
        .padding(.vertical, TPCSpacing.sm)
        .background(TPCColor.background)
    }
}

#Preview {
    GoalsStepView(model: AuthModel(
        repository: MockAuthRepository(),
        account: MockAccountRepository()
    ))
}
