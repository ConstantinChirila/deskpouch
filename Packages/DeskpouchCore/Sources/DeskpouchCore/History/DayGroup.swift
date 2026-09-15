import Foundation

/// Groups history rows by calendar day with the labels the History view shows: "Today", "Yesterday",
/// then "Mon 8 Sep", with the year added once the day is outside the current year.
public enum DayGroup {
    public struct Section<Item>: Identifiable {
        public let id: Date
        public let label: String
        public var items: [Item]
    }

    public static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = sameYear ? "EEE d MMM" : "EEE d MMM yyyy"
        return formatter.string(from: date)
    }

    /// Keeps the incoming order (newest first) and starts a new section whenever the day changes.
    public static func sections<Item>(_ items: [Item], date: (Item) -> Date, now: Date = Date(), calendar: Calendar = .current) -> [Section<Item>] {
        var sections: [Section<Item>] = []
        for item in items {
            let day = calendar.startOfDay(for: date(item))
            if let last = sections.last, last.id == day {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(Section(id: day, label: label(for: day, now: now, calendar: calendar), items: [item]))
            }
        }
        return sections
    }

    /// "10:41" in the user's clock style.
    public static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
