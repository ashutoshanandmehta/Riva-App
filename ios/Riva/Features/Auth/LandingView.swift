import SwiftUI

/// The marketing landing page, first thing a new user sees. Teal hero
/// gradient, three feature highlights, one call to action.
struct LandingView: View {
    @Bindable var model: AuthModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RivaColor.heroTop, RivaColor.heroMid, RivaColor.heroBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: RivaSpacing.lg) {
                Spacer(minLength: RivaSpacing.xl)

                VStack(spacing: RivaSpacing.sm) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            .white.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    Text("Riva Health")
                        .font(RivaFont.cardTitle)
                        .foregroundStyle(.white)
                }

                VStack(spacing: RivaSpacing.sm) {
                    Text("Your AI Health Companion for GLP-1 Success")
                        .font(RivaFont.screenTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Personalized insights, medication tracking, and Medicare Bridge Program eligibility checking, all in one place.")
                        .font(RivaFont.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, RivaSpacing.xl)

                VStack(spacing: RivaSpacing.sm) {
                    featureCard(
                        icon: "sparkles",
                        title: "AI-Powered Guidance",
                        subtitle: "Real-time health adjustments based on your data."
                    )
                    featureCard(
                        icon: "building.columns",
                        title: "Medicare Bridge Access",
                        subtitle: "Instant eligibility checks for program benefits."
                    )
                    featureCard(
                        icon: "chart.bar.xaxis",
                        title: "Track Your Progress",
                        subtitle: "Visualized dosage and nutrient monitoring."
                    )
                }
                .padding(.horizontal, RivaSpacing.screenMargin)

                Spacer()

                Button {
                    model.getStarted()
                } label: {
                    HStack(spacing: RivaSpacing.xs) {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(RivaColor.heroBottom)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white, in: Capsule())
                }
                .padding(.horizontal, RivaSpacing.screenMargin)
                .padding(.bottom, RivaSpacing.md)
            }
        }
    }

    private func featureCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: RivaSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(RivaFont.cardTitle)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(RivaFont.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(RivaSpacing.md)
        .background(
            .white.opacity(0.13),
            in: RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RivaRadius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
    }
}

#Preview {
    LandingView(model: AuthModel(
        repository: MockAuthRepository(),
        account: MockAccountRepository()
    ))
}
