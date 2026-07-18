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

/// Cached date parsing for the wire formats the account endpoints use.
enum AccountDates {

    /// Parses "2026-07-12T09:00:00Z", with or without fractional seconds.
    static func timestamp(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? iso.date(from: string)
    }

    static func day(_ string: String) -> Date? {
        dayFormatter.date(from: string)
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let iso = ISO8601DateFormatter()

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Icon-in-a-circle header shared by every account sheet.
struct AccountSheetHeader: View {
    let sheet: AccountSheet

    var body: some View {
        VStack(spacing: RivaSpacing.sm) {
            Image(systemName: sheet.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(RivaColor.brand)
                .frame(width: 56, height: 56)
                .background(RivaColor.brandWash, in: Circle())
            Text(sheet.title)
                .font(RivaFont.sectionTitle)
                .foregroundStyle(RivaColor.textPrimary)
        }
    }
}

/// Checkmark confirmation shown briefly before a sheet dismisses itself.
struct AccountSavedView: View {
    let message: String

    var body: some View {
        VStack(spacing: RivaSpacing.md) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(RivaColor.textOnBrand)
                .frame(width: 56, height: 56)
                .background(RivaColor.brand, in: Circle())
            Text(message)
                .font(RivaFont.body)
                .foregroundStyle(RivaColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RivaSpacing.xl)
            Spacer()
        }
    }
}

/// Compact in-sheet load failure with a retry affordance.
struct AccountLoadFailedView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: RivaSpacing.md) {
            Spacer()
            Text(message)
                .font(RivaFont.body)
                .foregroundStyle(RivaColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RivaSpacing.xxl)
            Button("Try again", action: onRetry)
                .font(RivaFont.captionEmphasized)
                .foregroundStyle(RivaColor.brand)
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
        VStack(alignment: .leading, spacing: RivaSpacing.xs) {
            Text(label)
                .rivaOverline()
            HStack(spacing: RivaSpacing.xs) {
                TextField(prompt, text: $text)
                    .keyboardType(keyboard)
                    .font(RivaFont.body)
                    .foregroundStyle(RivaColor.textPrimary)
                if let unit {
                    Text(unit)
                        .font(RivaFont.metricUnit)
                        .foregroundStyle(RivaColor.textSecondary)
                }
            }
            .padding(.horizontal, RivaSpacing.md)
            .padding(.vertical, 12)
            .background(
                RivaColor.fillNeutral,
                in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
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
                .font(RivaFont.captionEmphasized)
                .foregroundStyle(isSelected ? RivaColor.textOnBrand : RivaColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isSelected ? RivaColor.brandDeep : RivaColor.fillNeutral,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
