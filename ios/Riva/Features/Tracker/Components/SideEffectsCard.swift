import SwiftUI

/// Side-effects tile — body figure with the current reported symptom.
/// Tapping the tile opens the body-map logger; "+" logs a new symptom
/// (both placeholders for now).
struct SideEffectsCard: View {
    let report: SideEffectReport
    let onOpen: () -> Void
    let onAdd: () -> Void

    var body: some View {
        Button(action: onOpen) {
            RivaCard {
                VStack(alignment: .leading, spacing: RivaSpacing.sm) {
                    Text("Side effects")
                        .rivaOverline()

                    figure
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottomTrailing) {
                            RivaQuickAddButton(accessibilityLabel: "Log a side effect", action: onAdd)
                                .padding(6)
                        }

                    Text(report.summary)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(severityColor)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Side effects: \(report.summary)")
    }

    private var figure: some View {
        Image(systemName: "figure.stand")
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(RivaColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RivaColor.fillNeutral.opacity(0.6),
                in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
            )
    }

    private var severityColor: Color {
        switch report.severity {
        case .none: RivaColor.textSecondary
        case .mild, .moderate: RivaColor.danger
        case .severe: RivaColor.danger
        }
    }
}

#Preview {
    SideEffectsCard(report: MockTrackerRepository.dashboard().sideEffect, onOpen: {}, onAdd: {})
        .frame(width: 170, height: 200)
        .padding()
        .background(RivaColor.background)
}
