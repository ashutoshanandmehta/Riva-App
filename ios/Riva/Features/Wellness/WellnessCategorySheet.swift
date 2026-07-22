import SwiftUI

struct WellnessCategorySheet: View {
    let category: WellnessCategory
    @State private var showIshaKriya = false
    @State private var showNSDR = false
    @State private var selectedYoga: YogaSession? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch category {
                case .meditation: meditationList
                case .yoga:       yogaList
                case .exercise:   comingSoon
                }
            }
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.large)
            .background(RivaColor.background)
            .toolbarBackground(RivaColor.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showIshaKriya) { IshaKriyaView() }
        .fullScreenCover(isPresented: $showNSDR) { NSDRView() }
        .fullScreenCover(item: $selectedYoga) { YogaSessionView(session: $0) }
    }

    // MARK: Meditation

    private var meditationList: some View {
        ScrollView {
            LazyVStack(spacing: RivaSpacing.md) {
                practiceCard(
                    icon: "moon.stars.fill",
                    iconStyle: .gradient,
                    title: "Isha Kriya",
                    subtitle: "by Sadhguru · Isha Foundation",
                    duration: "21 min",
                    action: { showIshaKriya = true }
                )
                practiceCard(
                    icon: "brain.head.profile",
                    iconStyle: .soft,
                    title: "NSDR",
                    subtitle: "by Andrew Huberman · Huberman Lab",
                    duration: "10 min",
                    action: { showNSDR = true }
                )
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
            .padding(.top, RivaSpacing.sm)
        }
    }

    // MARK: Yoga

    private var yogaList: some View {
        ScrollView {
            LazyVStack(spacing: RivaSpacing.md) {
                ForEach(YogaSession.all) { session in
                    practiceCard(
                        icon: session.icon,
                        iconStyle: .soft,
                        title: session.title,
                        subtitle: session.host,
                        duration: session.duration,
                        action: { selectedYoga = session }
                    )
                }
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
            .padding(.top, RivaSpacing.sm)
        }
    }

    // MARK: Exercise (coming soon)

    private var comingSoon: some View {
        VStack(spacing: RivaSpacing.md) {
            Spacer()
            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundStyle(RivaColor.brand)
            Text("Coming Soon")
                .font(RivaFont.sectionTitle)
                .foregroundStyle(RivaColor.textPrimary)
            Text("Exercise programs are on the way.")
                .font(RivaFont.body)
                .foregroundStyle(RivaColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, RivaSpacing.screenMargin)
    }

    // MARK: Shared card

    private enum IconStyle { case gradient, soft }

    private func practiceCard(
        icon: String,
        iconStyle: IconStyle,
        title: String,
        subtitle: String,
        duration: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RivaCard {
                HStack(alignment: .center, spacing: RivaSpacing.md) {
                    iconChip(icon: icon, style: iconStyle)
                    VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                        HStack(spacing: RivaSpacing.xs) {
                            Text(title)
                                .font(RivaFont.cardTitle)
                                .foregroundStyle(RivaColor.textPrimary)
                            Text(duration.uppercased())
                                .rivaOverline(RivaColor.brand)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(RivaColor.brandWash, in: Capsule())
                        }
                        Text(subtitle)
                            .font(RivaFont.footnote)
                            .foregroundStyle(RivaColor.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RivaColor.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func iconChip(icon: String, style: IconStyle) -> some View {
        if style == .gradient {
            ZStack {
                RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
                    .fill(LinearGradient(
                        colors: [RivaColor.brand, RivaColor.brandDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
                    .fill(RivaColor.brandSoft)
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(RivaColor.brand)
            }
        }
    }
}
