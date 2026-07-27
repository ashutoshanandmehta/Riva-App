import SwiftUI

struct LandingView: View {
    @Bindable var model: AuthModel

    @State private var heroIndex = 0

    private let heroImages = ["LandingHero1", "LandingHero2", "LandingHero3", "LandingHero4"]
    private let heroTimer = Timer.publish(every: 4.2, on: .main, in: .common).autoconnect()

    // Cormorant Garamond variable font — loaded via UIAppFonts in Info.plist.
    // PostScript name of the default instance is "CormorantGaramond-Light";
    // falls back to system New York serif if the file is missing from the bundle.
    private let headlineFont: Font = {
        if UIFont(name: "CormorantGaramond-Light", size: 44) != nil {
            return Font.custom("Cormorant Garamond", fixedSize: 44).weight(.medium)
        }
        return Font.system(size: 44, weight: .medium, design: .serif)
    }()

    private let italicFont: Font = {
        if UIFont(name: "CormorantGaramond-LightItalic", size: 33) != nil {
            return Font.custom("Cormorant Garamond", fixedSize: 33).italic()
        }
        return Font.system(size: 33, weight: .regular, design: .serif).italic()
    }()

    var body: some View {
        ZStack {
            // 1. Dark base fills full screen
            TPCColor.heroBackground.ignoresSafeArea()

            // 2. Full-bleed hero photos
            ZStack {
                ForEach(Array(heroImages.enumerated()), id: \.offset) { index, name in
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .opacity(heroIndex == index ? 1 : 0)
                        .animation(.easeInOut(duration: 1.2), value: heroIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 3. Gradient — maps design's 500/844px image crop to full-screen SwiftUI.
            //    Gradient is 100% opaque by 60% screen height so the text area below
            //    sits on solid dark regardless of what the hero photo contains.
            LinearGradient(
                stops: [
                    .init(color: TPCColor.heroBackground.opacity(0.62), location: 0.00),
                    .init(color: TPCColor.heroBackground.opacity(0.30), location: 0.18),
                    .init(color: TPCColor.heroBackground.opacity(0.45), location: 0.41),
                    .init(color: TPCColor.heroBackground.opacity(1.00), location: 0.60),
                    .init(color: TPCColor.heroBackground.opacity(1.00), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 4. Content
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 20)
                    .padding(.horizontal, 26)

                Spacer()

                sealAndWordmark

                Spacer()

                bottomBlock
                    .padding(.horizontal, 18)
                    .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(heroTimer) { _ in
            withAnimation { heroIndex = (heroIndex + 1) % heroImages.count }
        }
    }

    // MARK: Progress dots

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<heroImages.count, id: \.self) { i in
                Capsule()
                    .fill(i == heroIndex
                          ? TPCColor.accentPale
                          : TPCColor.accentPale.opacity(0.28))
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.4), value: heroIndex)
            }
        }
    }

    // MARK: Seal + wordmark

    private var sealAndWordmark: some View {
        VStack(spacing: 12) {
            sealView
            VStack(spacing: 3) {
                // 27px Bricolage Grotesque Bold (-0.03em tracking) from design
                Text("The Peptide Company")
                    .font(Font.custom("Bricolage Grotesque", fixedSize: 27).weight(.bold))
                    .kerning(-0.81)
                    .foregroundStyle(Color(hex: 0xF6F2E8))
                    .shadow(color: TPCColor.heroBackground.opacity(0.6), radius: 7)

                // 11px DM Sans Bold, 0.24em tracking, uppercase from design
                Text("The peptides · The habits · Life")
                    .font(Font.custom("DM Sans", fixedSize: 11).weight(.bold))
                    .textCase(.uppercase)
                    .kerning(2.64)
                    .foregroundStyle(TPCColor.accentPale.opacity(0.9))
            }
        }
    }

    // Seal circle: the shared brand mark, in the brand grotesque and carrying a
    // drop shadow so it separates from the photo hero behind it.
    private var sealView: some View {
        TPCSeal(
            size: 104,
            font: Font.custom("Bricolage Grotesque", fixedSize: 21).weight(.heavy),
            shadow: true,
            glass: true
        )
    }

    // MARK: Bottom block

    private var bottomBlock: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Headline — Cormorant Garamond (or system New York serif fallback)
            VStack(alignment: .leading, spacing: 0) {
                Text("LOSE THE\nWEIGHT.")
                    .font(headlineFont)
                    .foregroundStyle(Color(hex: 0xF6F2E8))
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Build habits to keep it off.")
                    .font(italicFont)
                    .foregroundStyle(Color(hex: 0xA8C6A8))
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Trust badges
            HStack(spacing: 16) {
                trustBadge("Doctor-prescribed")
                trustBadge("Cancel anytime")
                Spacer()
            }

            // CTAs — defined inline to match design exactly (18px padding, 14.5px font)
            VStack(spacing: 10) {
                Button { model.getStarted() } label: {
                    Text("Check if you qualify")
                        .font(Font.custom("DM Sans", fixedSize: 14.5).weight(.bold))
                        .foregroundStyle(Color(hex: 0xFBF7EC))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(TPCColor.brand, in: Capsule())
                }
                .buttonStyle(.plain)

                Button { model.showLogin() } label: {
                    (Text("Already with us?  ")
                        .font(Font.custom("DM Sans", fixedSize: 11.5).weight(.medium))
                        .foregroundStyle(Color(hex: 0xF6F2E8, alpha: 0.62))
                    + Text("Sign in")
                        .font(Font.custom("DM Sans", fixedSize: 11.5).weight(.bold))
                        .foregroundStyle(TPCColor.accentPale))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func trustBadge(_ label: String) -> some View {
        HStack(spacing: 6) {
            Text("✓").foregroundStyle(TPCColor.accentGold)
            Text(label).foregroundStyle(Color(hex: 0xF6F2E8, alpha: 0.8))
        }
        .font(Font.custom("DM Sans", fixedSize: 11.5).weight(.bold))
    }
}

#Preview {
    LandingView(model: AuthModel(
        repository: MockAuthRepository(),
        account: MockAccountRepository()
    ))
}
