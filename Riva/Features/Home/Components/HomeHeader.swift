import SwiftUI

/// Top of the Home screen: brand row (logo + settings), greeting, and quote.
struct HomeHeader: View {
    let userName: String
    let quote: String
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RivaSpacing.md) {
            BrandTopBar(onSettings: onSettings)

            VStack(alignment: .leading, spacing: RivaSpacing.xxs) {
                Text("\(HomeViewModel.greeting()) \(userName)")
                    .font(RivaFont.screenTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text("\u{201C}\(quote)\u{201D}")
                    .font(RivaFont.footnote.italic())
                    .foregroundStyle(RivaColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HomeHeader(userName: "Sarah", quote: "Consistency is your superpower.") {}
        .padding()
        .background(RivaColor.background)
}
