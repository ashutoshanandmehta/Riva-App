import SwiftUI

/// Floating Liquid Glass bottom bar: four tabs around a central snap
/// (aperture) button.
struct RivaTabBar: View {
    @Environment(AppModel.self) private var appModel
    /// Drives the liquid slide of the selection pill between tabs.
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.leading) { tabButton($0) }
            snapButton
            ForEach(AppTab.trailing) { tabButton($0) }
        }
        .padding(.horizontal, RivaSpacing.xs)
        .padding(.vertical, RivaSpacing.xs)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .padding(.horizontal, RivaSpacing.md)
    }

    // MARK: Tabs

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = appModel.selectedTab == tab
        return Button {
            appModel.select(tab: tab)
        } label: {
            VStack(spacing: 3) {
                RivaIconView(icon: tab.icon, pointSize: 19, scale: tab.iconScale)
                    .frame(height: 22)
                Text(tab.title)
                    .font(RivaFont.tabLabel)
            }
            .foregroundStyle(isSelected ? RivaColor.brand : RivaColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                // Liquid selection pill — matched geometry makes it flow
                // to whichever tab is active.
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(RivaColor.brand.opacity(0.13))
                        .matchedGeometryEffect(id: "riva.tab.selection", in: selectionNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Snap button

    private var snapButton: some View {
        Button {
            appModel.toggleSnapMenu()
        } label: {
            Image(systemName: "camera.aperture")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(RivaColor.textOnBrand)
                .rotationEffect(.degrees(appModel.isSnapMenuOpen ? 45 : 0))
                .frame(width: RivaLayout.snapButtonSize, height: RivaLayout.snapButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(RivaColor.brandDeep).interactive(), in: Circle())
        .accessibilityLabel("Quick log")
        .accessibilityHint("Opens weight, water and food logging")
    }
}

#Preview {
    VStack {
        Spacer()
        RivaTabBar()
    }
    .background(RivaColor.background)
    .environment(AppModel())
}
