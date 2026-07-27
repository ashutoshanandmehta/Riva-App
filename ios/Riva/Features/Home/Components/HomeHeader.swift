import SwiftUI

/// Top of the Home screen's scrolling content: greeting + streak chip. The TPC
/// brand bar sits above it, pinned by `HomeView`.
struct HomeHeader: View {
    let userName: String
    let streak: Int

    var body: some View {
        HStack(alignment: .center, spacing: TPCSpacing.sm) {
            Text("Hey \(userName) — ")
                .font(TPCFont.screenTitle)
                .foregroundStyle(TPCColor.textPrimary)
            + Text("how's today going?")
                .font(TPCFont.screenTitle)
                .foregroundStyle(TPCColor.textSecondary)

            Spacer(minLength: 0)

            if streak > 0 {
                streakChip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streakChip: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.system(size: 11))
            Text("\(streak)d")
                .font(TPCFont.metricS)
                .foregroundStyle(TPCColor.accentLink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(TPCColor.brandSoft, in: Capsule())
        .overlay(Capsule().strokeBorder(TPCColor.brand.opacity(0.22), lineWidth: 1))
    }
}

#Preview {
    HomeHeader(userName: "Alex", streak: 42)
        .padding()
        .background(TPCColor.background)
}
