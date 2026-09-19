import Foundation

/// The gallery's date filter: a few presets instead of a range picker (10-gallery.md). Pure, so the bounds are
/// tested with a fixed clock and time zone.
public enum GalleryDatePreset: String, CaseIterable, Sendable {
    case any, today, week, month, year

    public var label: String {
        switch self {
        case .any: "Any time"
        case .today: "Today"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .year: "This year"
        }
    }

    /// Captures at or after this match; nil for `.any`. Whole days in the user's calendar: "Last 7 days" is
    /// today and the six days before it, from midnight.
    public func start(now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .any: return nil
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .year: return calendar.date(from: calendar.dateComponents([.year], from: now))
        }
    }
}
