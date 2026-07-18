import Foundation

/// Shared display formatting for domain values.
///
/// Formatters are cached statically — creating `DateFormatter`s per render is
/// expensive.
enum RivaFormat {

    // MARK: Weight

    /// "164.2" — one decimal, no unit.
    static func weight(_ lbs: Double) -> String {
        String(format: "%.1f", lbs)
    }

    /// "-1.2" — signed one-decimal delta.
    static func signedDelta(_ lbs: Double) -> String {
        String(format: "%+.1f", lbs).replacingOccurrences(of: "+", with: lbs > 0 ? "+" : "")
    }

    // MARK: Doses

    /// "12.5" / "5" — trims a trailing ".0".
    static func doseNumber(_ mg: Double) -> String {
        mg.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", mg)
            : String(format: "%.1f", mg)
    }

    /// "12.5 mg"
    static func doseMg(_ mg: Double) -> String {
        "\(doseNumber(mg)) mg"
    }

    /// "0.5mg" — compact form for inline labels ("Week 4 • 0.5mg").
    static func doseMgCompact(_ mg: Double) -> String {
        "\(doseNumber(mg))mg"
    }

    // MARK: Dates

    /// "15 Jul 2026 at 9:54 PM"
    static func shotDate(_ date: Date) -> String {
        shotDateFormatter.string(from: date)
    }

    /// "Sunday"
    static func weekdayName(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    /// "Sunday, 8:00 AM"
    static func doseSchedule(_ date: Date) -> String {
        scheduleFormatter.string(from: date)
    }

    /// "Aug 18, 2026"
    static func mediumDate(_ date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }

    /// "72h" — whole hours until `date`, clamped at zero.
    static func hoursRemaining(until date: Date, from now: Date = .now) -> String {
        let hours = max(Int(ceil(date.timeIntervalSince(now) / 3600)), 0)
        return "\(hours)h"
    }

    // MARK: Wellness

    /// "7h 20m"
    static func sleepDuration(minutes: Int) -> String {
        "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// "92%"
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// "85" — whole grams.
    static func grams(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    /// "June 15 — June 21"
    static func weekRange(_ interval: DateInterval) -> String {
        "\(monthDay(interval.start)) — \(monthDay(interval.end))"
    }

    /// "June 18"
    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    /// "1,640" — grouped whole number (kcal).
    static func wholeNumber(_ value: Double) -> String {
        groupedNumberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    /// "2.4L / day"
    static func litersPerDay(_ liters: Double) -> String {
        let text = liters.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", liters)
            : String(format: "%.1f", liters)
        return "\(text)L / day"
    }

    // MARK: Cached formatters

    private static let shotDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let scheduleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, h:mm a"
        return formatter
    }()

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter
    }()

    private static let groupedNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
