import Foundation

/// The short time phrases the menubar item, the Tools row and the pills use. Pure; the calendar and locale are
/// injected so tests pin them.
public struct CalendarText: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    /// Whole minutes until `date`, rounded up, never below 1: at 14:25:30 an event at 14:30 is "in 5 min".
    static func minutesUntil(_ date: Date, from now: Date) -> Int {
        max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// "in 45 min", "in 1 h 5 min", "in 2 h".
    public func countdown(to start: Date, from now: Date) -> String {
        "in " + duration(minutes: Self.minutesUntil(start, from: now))
    }

    /// "23 min left", "1 h 10 min left".
    public func remaining(until end: Date, from now: Date) -> String {
        duration(minutes: Self.minutesUntil(end, from: now)) + " left"
    }

    func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Format styles cache their formatters internally, unlike a `DateFormatter` built per call; these run in
    /// every agenda row and pill render.
    private var base: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// "14:30", in the user's 12 or 24 hour style.
    public func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// For a heads-up about a later day: "tomorrow 13:30", "Sat 10:00" within the week, "Sat 3 Oct" beyond.
    public func laterDay(_ start: Date, isAllDay: Bool, from now: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
        let time = isAllDay ? "" : " " + clock(start)
        if days == 1 { return "tomorrow" + time }
        if days < 7 { return start.formatted(base.weekday(.abbreviated)) + time }
        return start.formatted(base.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Titles in the menubar stop at about 20 characters.
    public static func trimmed(_ title: String, to limit: Int = 20) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return clean.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
