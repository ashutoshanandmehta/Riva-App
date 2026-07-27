import SwiftUI

/// Shared chrome for the history and info sheets: title on the left, a
/// round close button on the right (mirrors the snap scan header).
struct DetailSheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(TPCFont.sectionTitle)
                .foregroundStyle(TPCColor.textPrimary)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TPCColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(TPCColor.fillNeutral, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, TPCSpacing.screenMargin)
        .padding(.vertical, TPCSpacing.sm)
    }
}

/// Centered empty state for a history sheet with nothing to show yet.
struct DetailEmptyState: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: TPCSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(TPCColor.textSecondary)
            Text(message)
                .font(TPCFont.body)
                .foregroundStyle(TPCColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
        .padding(.horizontal, TPCSpacing.xxl)
    }
}

/// Parses and formats the wire date strings shown on the detail sheets.
enum DetailDate {

    /// Accepts ISO8601 timestamps with or without fractional seconds, plus
    /// plain "yyyy-MM-dd" day strings.
    static func parse(_ raw: String) -> Date? {
        isoFractional.date(from: raw) ?? iso.date(from: raw) ?? dayOnly.date(from: raw)
    }

    /// "Thursday, Jul 17"
    static func dayLabel(_ raw: String) -> String {
        guard let date = parse(raw) else { return raw }
        return dayLabelFormatter.string(from: date)
    }

    /// "Jul 2"
    static func shortDayLabel(_ raw: String) -> String {
        guard let date = parse(raw) else { return raw }
        return shortDayFormatter.string(from: date)
    }

    // MARK: Cached formatters

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()

    private static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
