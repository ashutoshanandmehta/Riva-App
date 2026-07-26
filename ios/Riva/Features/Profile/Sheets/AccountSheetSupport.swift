import SwiftUI

// Shared building blocks for the account settings sheets, mirroring the
// quick-log sheet's shell: icon header, saved confirmation, form fields.

/// Weekday names and parsing shared by the injection day and reminder flows.
enum RivaWeekday {
    static let names = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    /// First weekday name found in free text ("Weekly on Saturday"), if any.
    static func name(in text: String?) -> String? {
        guard let lowered = text?.lowercased() else { return nil }
        return names.first { lowered.contains($0.lowercased()) }
    }

    /// 1-based calendar index (Sunday = 1), matching `DateComponents.weekday`.
    static func calendarIndex(of name: String) -> Int {
        (names.firstIndex(of: name) ?? 0) + 1
    }
}

// Date parsing moved to `Core/Support/AccountDates.swift` so Core types can
// use it without depending on Features.

/// Icon-in-a-circle header shared by every account sheet.
struct AccountSheetHeader: View {
    let sheet: AccountSheet

    var body: some View {
        VStack(spacing: TPCSpacing.sm) {
            Image(systemName: sheet.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(TPCColor.brand)
                .frame(width: 56, height: 56)
                .background(TPCColor.brandWash, in: Circle())
            Text(sheet.title)
                .font(TPCFont.sectionTitle)
                .foregroundStyle(TPCColor.textPrimary)
        }
    }
}

/// Checkmark confirmation shown briefly before a sheet dismisses itself.
struct AccountSavedView: View {
    let message: String

    var body: some View {
        VStack(spacing: TPCSpacing.md) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(TPCColor.textOnBrand)
                .frame(width: 56, height: 56)
                .background(TPCColor.brand, in: Circle())
            Text(message)
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TPCSpacing.xl)
            Spacer()
        }
    }
}

/// Compact in-sheet load failure with a retry affordance.
struct AccountLoadFailedView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: TPCSpacing.md) {
            Spacer()
            Text(message)
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TPCSpacing.xxl)
            Button("Try again", action: onRetry)
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(TPCColor.brand)
            Spacer()
        }
    }
}

/// Overline label above a filled text field, with an optional trailing unit.
struct AccountLabeledField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var unit: String?
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: TPCSpacing.xs) {
            Text(label)
                .rivaOverline()
            HStack(spacing: TPCSpacing.xs) {
                TextField(prompt, text: $text)
                    .keyboardType(keyboard)
                    .font(TPCFont.body)
                    .foregroundStyle(TPCColor.textPrimary)
                if let unit {
                    Text(unit)
                        .font(TPCFont.metricUnit)
                        .foregroundStyle(TPCColor.textSecondary)
                }
            }
            .padding(.horizontal, TPCSpacing.md)
            .padding(.vertical, 12)
            .background(
                TPCColor.fillNeutral,
                in: RoundedRectangle(cornerRadius: TPCRadius.tile, style: .continuous)
            )
        }
    }
}

/// Capsule selection chip, matching the quick-log sheet's chips.
struct AccountChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TPCFont.captionEmphasized)
                .foregroundStyle(isSelected ? TPCColor.textOnBrand : TPCColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isSelected ? TPCColor.brandDeep : TPCColor.fillNeutral,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
