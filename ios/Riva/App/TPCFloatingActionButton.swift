import SwiftUI

/// Floating + action button — anchored bottom-right above the tab bar.
///
/// Expands to three action pills: Log food (opens scanner), Log water,
/// Log weight. The + rotates to × when the fan is open.
struct TPCFloatingActionButton: View {
    @Environment(AppModel.self) private var appModel

    private let actions: [(icon: String, label: String, action: SnapAction)] = [
        ("🍽", "Log food",   .food),
        ("💧", "Log water",  .water),
        ("⚖️", "Log weight", .weight)
    ]

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if appModel.isFABOpen {
                actionPills
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.9))
                        )
                    )
            }

            fabButton
        }
    }

    // MARK: Action pills

    private var actionPills: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(actions.indices.reversed(), id: \.self) { index in
                let item = actions[index]
                Button {
                    appModel.open(snapAction: item.action)
                } label: {
                    HStack(spacing: 9) {
                        Text(item.icon).font(.system(size: 14))
                        Text(item.label)
                            .font(TPCFont.captionEmphasized)
                            .foregroundStyle(TPCColor.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(TPCColor.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(TPCColor.surfaceOutline, lineWidth: 1))
                    .shadow(color: TPCColor.brandDeep.opacity(0.22), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75).delay(Double(actions.count - 1 - index) * 0.05)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))
                    )
                )
            }
        }
    }

    // MARK: FAB button

    private var fabButton: some View {
        Button {
            appModel.toggleFAB()
        } label: {
            Text(appModel.isFABOpen ? "×" : "+")
                .font(.system(size: appModel.isFABOpen ? 26 : 22, weight: .medium))
                .foregroundStyle(TPCColor.textOnInversePrimary)
                .frame(width: TPCLayout.fabSize, height: TPCLayout.fabSize)
                .background(TPCColor.surfaceInverse, in: Circle())
                .overlay(
                    Circle().strokeBorder(TPCColor.accentPale.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: TPCColor.brandDeep.opacity(0.55), radius: 14, x: 0, y: 7)
                .rotationEffect(.degrees(appModel.isFABOpen ? 45 : 0))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: appModel.isFABOpen)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appModel.isFABOpen ? "Close menu" : "Quick actions")
    }
}

#Preview {
    ZStack(alignment: .bottomTrailing) {
        TPCColor.background.ignoresSafeArea()
        TPCFloatingActionButton()
            .padding(.trailing, 20)
            .padding(.bottom, 120)
    }
    .environment(AppModel())
}
