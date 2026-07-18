import SwiftUI

/// Onboarding: pick health goals, then create the account with Google.
/// Returning users jump to login from the link up top.
struct GoalsStepView: View {
    @Bindable var model: AuthModel

    var body: some View {
        ZStack {
            RivaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: RivaSpacing.md) {
                        VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                            Text("What brings you to Riva?")
                                .font(RivaFont.screenTitle)
                                .foregroundStyle(RivaColor.textPrimary)
                            Text("Select all that apply to help us personalize your journey.")
                                .font(RivaFont.body)
                                .foregroundStyle(RivaColor.textSecondary)
                        }

                        ForEach(OnboardingGoal.allCases) { goal in
                            goalCard(goal)
                        }

                        intelligenceCard
                    }
                    .padding(.horizontal, RivaSpacing.screenMargin)
                    .padding(.bottom, RivaSpacing.xl)
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
                    .foregroundStyle(RivaColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(RivaColor.fillNeutral, in: Circle())
            }
            .accessibilityLabel("Back")

            Spacer()

            Button("Already a user? Log in") {
                model.showLogin()
            }
            .font(RivaFont.captionEmphasized)
            .foregroundStyle(RivaColor.brand)
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
        .padding(.vertical, RivaSpacing.sm)
    }

    private func goalCard(_ goal: OnboardingGoal) -> some View {
        let isSelected = model.selectedGoals.contains(goal)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                model.toggle(goal)
            }
        } label: {
            HStack(spacing: RivaSpacing.md) {
                Image(systemName: goal.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? RivaColor.textOnBrand : RivaColor.brand)
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected ? RivaColor.brand : RivaColor.brandWash,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(RivaFont.cardTitle)
                        .foregroundStyle(RivaColor.textPrimary)
                    Text(goal.subtitle)
                        .font(RivaFont.footnote)
                        .foregroundStyle(RivaColor.textSecondary)
                }
                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? RivaColor.brand : RivaColor.textTertiary)
            }
            .padding(RivaSpacing.md)
            .background(
                RivaColor.surface,
                in: RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? RivaColor.brand.opacity(0.5) : RivaColor.surfaceOutline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var intelligenceCard: some View {
        HStack(alignment: .top, spacing: RivaSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RivaColor.brand)
                .frame(width: 38, height: 38)
                .background(RivaColor.surface, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Riva Intelligence")
                    .font(RivaFont.cardTitle)
                    .foregroundStyle(RivaColor.brand)
                Text("Based on clinical data, users who track muscle preservation alongside GLP-1 therapy see 40% better outcomes in long-term metabolic health.")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
        .padding(RivaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RivaColor.brandWash,
            in: RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous)
        )
    }

    private var footer: some View {
        VStack(spacing: RivaSpacing.xs) {
            if let notice = model.notice {
                Text(notice)
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RivaSpacing.lg)
            }
            Button {
                Task { await model.continueWithGoogle(fromLogin: false) }
            } label: {
                if model.isWorking {
                    ProgressView().tint(RivaColor.textOnBrand)
                } else {
                    Text("Create account with Google")
                }
            }
            .buttonStyle(.rivaPrimary)
            .disabled(model.isWorking)
            .padding(.horizontal, RivaSpacing.screenMargin)

            Text("Your goals sync to your account after sign in.")
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textTertiary)
        }
        .padding(.vertical, RivaSpacing.sm)
        .background(RivaColor.background)
    }
}

#Preview {
    GoalsStepView(model: AuthModel(
        repository: MockAuthRepository(),
        account: MockAccountRepository()
    ))
}
