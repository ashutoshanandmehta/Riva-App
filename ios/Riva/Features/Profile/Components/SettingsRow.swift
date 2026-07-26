import SwiftUI

/// Standard settings list row: icon chip, title, optional subtitle, chevron.
struct SettingsRow: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TPCSpacing.sm) {
                RivaIconChip(systemImage: systemImage, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TPCColor.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(TPCColor.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TPCColor.textTertiary)
            }
            .padding(TPCSpacing.sm)
            .background(
                TPCColor.surface,
                in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
            )
            .rivaSurfaceOutline(cornerRadius: TPCRadius.tile)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}

#Preview {
    VStack(spacing: 8) {
        SettingsRow(systemImage: "syringe", title: "Tirzepatide", subtitle: "Current Dose: 12.5mg") {}
        SettingsRow(systemImage: "bell", title: "Notifications", subtitle: nil) {}
    }
    .padding()
    .background(TPCColor.background)
}
