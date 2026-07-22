import SwiftUI

enum WellnessCategory: String, Identifiable {
    case yoga, exercise, meditation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yoga:       "Yoga"
        case .exercise:   "Exercise"
        case .meditation: "Meditation"
        }
    }

    var icon: String {
        switch self {
        case .yoga:       "figure.yoga"
        case .exercise:   "figure.run"
        case .meditation: "moon.stars.fill"
        }
    }
}

struct WellnessView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedCategory: WellnessCategory? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandTopBar(onSettings: { appModel.showProfile() })
                .padding(.horizontal, RivaSpacing.screenMargin)
                .padding(.top, RivaSpacing.xs)

            Text("Wellness")
                .font(RivaFont.screenTitle)
                .foregroundStyle(RivaColor.textPrimary)
                .padding(.horizontal, RivaSpacing.screenMargin)
                .padding(.top, RivaSpacing.xs)

            Spacer()

            triangleLayout
                .padding(.bottom, RivaLayout.tabBarClearance + RivaSpacing.xl)
        }
        .background(RivaColor.background)
        .sheet(item: $selectedCategory) { category in
            WellnessCategorySheet(category: category)
        }
    }

    // MARK: Triangle

    private var triangleLayout: some View {
        GeometryReader { geo in
            let cx   = geo.size.width / 2
            let cy   = geo.size.height / 2
            let side = min(geo.size.width * 0.62, 230.0)
            let th   = side * sqrt(3) / 2

            let topLeft  = CGPoint(x: cx - side / 2, y: cy - th / 2)
            let topRight = CGPoint(x: cx + side / 2, y: cy - th / 2)
            let bottom   = CGPoint(x: cx,             y: cy + th / 2)

            ZStack {
                Path { path in
                    path.move(to: topLeft)
                    path.addLine(to: topRight)
                    path.addLine(to: bottom)
                    path.closeSubpath()
                }
                .stroke(RivaColor.brandSoft, lineWidth: 1.5)

                categoryNode(.yoga,       at: topLeft)
                categoryNode(.exercise,   at: topRight)
                categoryNode(.meditation, at: bottom)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    private func categoryNode(_ category: WellnessCategory, at point: CGPoint) -> some View {
        Button { selectedCategory = category } label: {
            VStack(spacing: RivaSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [RivaColor.brand, RivaColor.brandDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .shadow(color: RivaColor.brand.opacity(0.3), radius: 14, y: 6)

                    Image(systemName: category.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text(category.title)
                    .font(RivaFont.captionEmphasized)
                    .foregroundStyle(RivaColor.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .position(point)
    }
}

#Preview {
    WellnessView()
        .environment(AppModel())
}
