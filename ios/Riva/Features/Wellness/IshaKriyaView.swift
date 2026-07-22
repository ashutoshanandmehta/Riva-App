import SwiftUI

struct IshaKriyaView: View {
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
                Text("Isha Kriya")
                    .font(RivaFont.screenTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text("by Sadhguru · Isha Foundation")
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

                YouTubePlayerView(videoID: "EwQkfoKxRvo")
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous))

                HStack(spacing: RivaSpacing.md) {
                    metaStat(icon: "clock", text: "21 min")
                    metaStat(icon: "repeat", text: "Daily")
                    metaStat(icon: "person.fill", text: "All levels")
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
                Text("Isha Kriya is a simple yet potent meditation offered freely by Sadhguru. Practiced daily for 48 days, it can bring clarity, stillness, and a natural sense of wellbeing — a meaningful complement to your GLP-1 journey.")
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

                prepStep(icon: "figure.mind.and.body",
                         text: "Sit with your spine erect — on a chair or cross-legged on the floor")
                prepStep(icon: "hand.raised",
                         text: "Rest your hands on your thighs, palms facing upward")
                prepStep(icon: "eye.slash",
                         text: "Keep eyes 2/3 closed, gaze directed down along your nose")
                prepStep(icon: "bell.slash",
                         text: "Find a quiet space and minimise disturbances for the full session")
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
    IshaKriyaView()
}
