import SwiftUI

/// The three quick-log actions (Weight, Water, Food) that fan out radially
/// above the central snap button.
///
/// Lives directly above `RivaTabBar` in the same centered column, so the fan
/// origin lines up with the aperture button. `GlassEffectContainer` lets the
/// glass buttons blend fluidly while animating.
struct SnapRadialFan: View {
    let isOpen: Bool
    let onSelect: (SnapAction) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            ZStack(alignment: .bottom) {
                // Invisible spacer defines the fan's coordinate space, so the
                // tab bar below never shifts when the fan appears.
                Color.clear
                    .frame(height: RivaLayout.snapFanRadius + RivaLayout.snapActionSize + 24)

                // Buttons must be *removed* when closed — glass effects inside
                // a GlassEffectContainer keep rendering even at opacity 0.
                if isOpen {
                    ForEach(SnapAction.allCases) { action in
                        fanButton(action)
                            .offset(offset(for: action))
                            .transition(.scale(scale: 0.1).combined(with: .opacity))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
    }

    // MARK: Geometry

    /// Radial offset from the fan origin (bottom center, just above the
    /// aperture button).
    private func offset(for action: SnapAction) -> CGSize {
        let angle = Angle(degrees: action.fanAngleDegrees).radians
        return CGSize(
            width: cos(angle) * RivaLayout.snapFanRadius,
            height: -sin(angle) * (RivaLayout.snapFanRadius - 42)
        )
    }

    // MARK: Button

    private func fanButton(_ action: SnapAction) -> some View {
        Button {
            onSelect(action)
        } label: {
            VStack(spacing: RivaSpacing.xs) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(RivaColor.brand)
                    .frame(width: RivaLayout.snapActionSize, height: RivaLayout.snapActionSize)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())

                Text(action.title)
                    .rivaOverline(RivaColor.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(RivaColor.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(action.title)")
    }
}

#Preview {
    struct FanPreview: View {
        @State private var open = true
        var body: some View {
            VStack {
                Spacer()
                SnapRadialFan(isOpen: open) { _ in }
                Button("Toggle") { withAnimation { open.toggle() } }
                    .padding(.bottom, 40)
            }
            .background(RivaColor.background)
        }
    }
    return FanPreview()
}
