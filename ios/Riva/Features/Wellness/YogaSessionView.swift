import SwiftUI

struct YogaSession: Identifiable {
    let id: String
    let title: String
    let host: String
    let duration: String
    let videoID: String
    let icon: String
    let description: String
    let prepSteps: [(icon: String, text: String)]
}

extension YogaSession {
    static let all: [YogaSession] = [
        YogaSession(
            id: "beginners",
            title: "Yoga for Beginners",
            host: "Yoga with Adriene",
            duration: "~20 min",
            videoID: "j7rKKpwdXNE",
            icon: "figure.yoga",
            description: "A gentle introduction to yoga with Adriene Mishler. Perfect if you're new to yoga or returning after a break — no prior experience needed.",
            prepSteps: [
                ("tshirt", "Wear loose, comfortable clothing you can move freely in"),
                ("rectangle.portrait", "Clear a mat-sized space around you"),
                ("drop.fill", "Keep a glass of water nearby"),
                ("fork.knife.circle", "Avoid eating at least 1–2 hours before the session"),
            ]
        ),
        YogaSession(
            id: "weightloss",
            title: "Yoga for Weight Loss",
            host: "Yoga with Adriene",
            duration: "~35 min",
            videoID: "6rh6pVGTqRU",
            icon: "flame.fill",
            description: "An energising flow to build strength, boost metabolism, and support your weight loss journey. Designed to complement your GLP-1 medication with mindful movement.",
            prepSteps: [
                ("tshirt", "Wear comfortable, breathable clothing"),
                ("rectangle.portrait", "Clear a 6×4 ft space and place your mat"),
                ("drop.fill", "Have water ready — this session builds heat"),
                ("clock", "Warm up with a few gentle stretches before starting"),
            ]
        ),
        YogaSession(
            id: "digestion",
            title: "Yoga for Digestion",
            host: "Yoga with Adriene",
            duration: "~25 min",
            videoID: "hbguV_f6XOo",
            icon: "leaf.fill",
            description: "Targeted poses to ease bloating, reduce nausea, and support gut health. Particularly beneficial for managing common GLP-1 side effects like digestive discomfort.",
            prepSteps: [
                ("fork.knife.circle", "Practice at least 2–3 hours after your last meal"),
                ("tshirt", "Wear loose clothing around your midsection"),
                ("rectangle.portrait", "Have a mat and a cushion or blanket for support"),
                ("heart", "Move gently — this is a restorative, not an intense session"),
            ]
        ),
    ]
}

// MARK: - Yoga Session Detail View

struct YogaSessionView: View {
    let session: YogaSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RivaSpacing.md) {
                header
                videoCard
                about
                preparation
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
            .padding(.top, RivaSpacing.xs)
        }
        .background(RivaColor.background)
        .contentMargins(.bottom, RivaSpacing.xxl, for: .scrollContent)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(RivaFont.screenTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text(session.host)
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RivaColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(RivaColor.fillNeutral, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, RivaSpacing.xs)
    }

    // MARK: Video

    private var videoCard: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                Text("GUIDED SESSION")
                    .rivaOverline(RivaColor.brand)

                YouTubePlayerView(videoID: session.videoID)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous))

                HStack(spacing: RivaSpacing.md) {
                    metaStat(icon: "clock", text: session.duration)
                    metaStat(icon: "person.fill", text: "All levels")
                    metaStat(icon: "repeat", text: "Weekly")
                }
            }
        }
    }

    // MARK: About

    private var about: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: RivaSpacing.xs) {
                Text("ABOUT")
                    .rivaOverline(RivaColor.brand)
                Text(session.description)
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Preparation

    private var preparation: some View {
        RivaCard(style: .tinted) {
            VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                Text("BEFORE YOU BEGIN")
                    .rivaOverline(RivaColor.brand)

                ForEach(session.prepSteps.indices, id: \.self) { index in
                    prepStep(icon: session.prepSteps[index].icon,
                             text: session.prepSteps[index].text)
                }
            }
        }
    }

    // MARK: Helpers

    private func metaStat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RivaColor.brand)
            Text(text)
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textSecondary)
        }
    }

    private func prepStep(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: RivaSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(RivaColor.brand)
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(RivaFont.footnote)
                .foregroundStyle(RivaColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    YogaSessionView(session: YogaSession.all[0])
}
