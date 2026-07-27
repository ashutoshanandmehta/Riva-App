import SwiftUI

/// Floating Liquid Glass bottom bar: five equal tabs.
/// The + FAB is a separate overlay in RootView.
struct RivaTabBar: View {
    @Environment(AppModel.self) private var appModel
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, TPCSpacing.xs)
        .padding(.vertical, TPCSpacing.xs)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .padding(.horizontal, TPCSpacing.md)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = appModel.selectedTab == tab
        return Button {
            appModel.select(tab: tab)
        } label: {
            VStack(spacing: 3) {
                RivaIconView(icon: tab.icon, pointSize: 19, scale: tab.iconScale)
                    .frame(height: 22)
                Text(tab.title)
                    .font(TPCFont.tabLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? TPCColor.brand : TPCColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(TPCColor.brand.opacity(0.13))
                        .matchedGeometryEffect(id: "tpc.tab.selection", in: selectionNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    VStack {
        Spacer()
        RivaTabBar()
    }
    .background(TPCColor.background)
    .environment(AppModel())
}
