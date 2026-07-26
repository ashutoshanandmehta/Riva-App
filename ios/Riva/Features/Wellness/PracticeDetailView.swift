import SwiftUI

/// Full-screen detail for any catalog practice: video, about, preparation,
/// and an explicit "Mark complete" action (completion is a deliberate tap,
/// never inferred from dismissal). `markComplete` is nil when the backend
/// has no wellness support — the button silently disappears.
struct PracticeDetailView: View {
    let practice: WellnessPractice
    var markComplete: (() async -> Bool)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var completionPhase: CompletionPhase = .idle

    private enum CompletionPhase {
        case idle, saving, done, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TPCSpacing.md) {
                header
                videoCard
                about
                preparation
                if markComplete != nil {
                    completeButton
                }
            }
            .padding(.horizontal, TPCSpacing.screenMargin)
            .padding(.top, TPCSpacing.xs)
        }
        .background(TPCColor.background)
        .contentMargins(.bottom, TPCSpacing.xxl, for: .scrollContent)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(practice.title)
                    .font(TPCFont.screenTitle)
                    .foregroundStyle(TPCColor.textPrimary)
                Text(practice.subtitle)
                    .font(TPCFont.footnote)
                    .foregroundStyle(TPCColor.textSecondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TPCColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(TPCColor.fillNeutral, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, TPCSpacing.xs)
    }

    // MARK: Video

    private var videoCard: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                Text("GUIDED SESSION")
                    .rivaOverline(TPCColor.brand)

                if let videoID = practice.videoID {
                    YouTubePlayerView(videoID: videoID)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous))

                    // Fallback for videos whose owner blocks embedding: opens
                    // the YouTube app / browser so the session is still usable.
                    Button {
                        let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")
                        if let url { openURL(url) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.rectangle.fill")
                            Text("Watch on YouTube")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(TPCFont.footnote)
                        .foregroundStyle(TPCColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    comingSoon
                }

                HStack(spacing: TPCSpacing.md) {
                    metaStat(icon: "clock", text: practice.durationText)
                    metaStat(icon: "person.fill", text: "All levels")
                    metaStat(icon: "repeat", text: practice.kind.title)
                }
            }
        }
    }

    private var comingSoon: some View {
        VStack(spacing: TPCSpacing.xs) {
            Image(systemName: "play.slash")
                .font(.system(size: 24))
                .foregroundStyle(TPCColor.brand)
            Text("Video coming soon")
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(
            TPCColor.brandWash,
            in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
        )
    }

    // MARK: About

    private var about: some View {
        RivaCard {
            VStack(alignment: .leading, spacing: TPCSpacing.xs) {
                Text("ABOUT")
                    .rivaOverline(TPCColor.brand)
                Text(practice.description)
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Preparation

    private var preparation: some View {
        RivaCard(style: .tinted) {
            VStack(alignment: .leading, spacing: TPCSpacing.sm) {
                Text("BEFORE YOU BEGIN")
                    .rivaOverline(TPCColor.brand)

                ForEach(practice.prepSteps.indices, id: \.self) { index in
                    prepStep(icon: practice.prepSteps[index].icon,
                             text: practice.prepSteps[index].text)
                }
            }
        }
    }

    // MARK: Mark complete

    private var completeButton: some View {
        Button {
            Task { await runMarkComplete() }
        } label: {
            switch completionPhase {
            case .idle:
                Label("Mark complete", systemImage: "checkmark")
            case .saving:
                Label("Saving…", systemImage: "checkmark")
            case .done:
                Label("Completed", systemImage: "checkmark.circle.fill")
            case .failed:
                Label("Couldn't save — try again", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.rivaPrimary)
        .disabled(completionPhase == .saving || completionPhase == .done)
    }

    private func runMarkComplete() async {
        guard let markComplete, completionPhase != .saving, completionPhase != .done else {
            return
        }
        completionPhase = .saving
        completionPhase = await markComplete() ? .done : .failed
    }

    // MARK: Helpers

    private func metaStat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TPCColor.brand)
            Text(text)
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textSecondary)
        }
    }

    private func prepStep(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: TPCSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(TPCColor.brand)
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(TPCFont.footnote)
                .foregroundStyle(TPCColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PracticeDetailView(practice: WellnessPractice.catalog[0]) { true }
}
