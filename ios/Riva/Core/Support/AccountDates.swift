import Foundation

/// Cached date parsing for the wire formats the backend uses.
///
/// Lives in Core because both `Core/Models` and the Profile sheets need it —
/// a Core type reaching up into Features would invert the layering.
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
