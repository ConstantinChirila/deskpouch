import Foundation

/// What the calendar shows at one moment: the menubar item, the Tools row line, today's rows and what Join
/// opens. Pure: built from the fetched events, the clock and the settings, rebuilt every 30 s and on each change.
public struct Agenda: Sendable {
    public enum Tint: Sendable, Equatable {
        /// More than 5 minutes out: plain template text.
        case plain
        /// The last 5 minutes before the start: amber capsule.
        case soon
        /// Running: mint capsule.
        case live
    }

    public struct Menubar: Sendable, Equatable {
        public var text: String
        public var tint: Tint
        public var eventID: String

        public init(text: String, tint: Tint, eventID: String) {
            self.text = text
            self.tint = tint
            self.eventID = eventID
        }
    }

    /// Which event the menubar and the Tools row talk about, and how.
    public enum Focus: Sendable, Equatable {
        case upcoming(CalendarEvent)
        case running(CalendarEvent)
    }

    /// A row in the Calendar view.
    public struct Row: Sendable, Equatable, Identifiable {
        public var event: CalendarEvent
        public var isPast: Bool
        public var isNext: Bool
        public var id: String { event.id }
    }

    static let soonWindow: TimeInterval = 5 * 60
    /// Join takes a call that started this long ago before looking ahead ("I'm late").
    static let joinLateWindow: TimeInterval = 10 * 60
    /// ...and looks this far ahead for the next one.
    static let joinAheadWindow: TimeInterval = 15 * 60

    public let now: Date
    public let settings: CalendarSettings
    public let text: CalendarText
    /// Timed events of today and beyond that count: not declined, not cancelled, calendar switched on. Sorted by
    /// start.
    public let timed: [CalendarEvent]
    /// Today's all-day events, same filter.
    public let allDayToday: [CalendarEvent]

    public init(events: [CalendarEvent], now: Date, settings: CalendarSettings, text: CalendarText = CalendarText()) {
        self.now = now
        self.settings = settings
        self.text = text
        let counted = events.filter {
            !$0.isCancelled && $0.attendance != .declined && !settings.hiddenCalendars.contains($0.calendarID)
        }
        timed = counted.filter { !$0.isAllDay }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        let cal = text.calendar
        allDayToday = counted.filter { $0.isAllDay && $0.start <= now && now < $0.end }
            .filter { cal.isDate($0.start, inSameDayAs: now) || $0.start < now }
            .sorted { $0.title < $1.title }
    }

    /// The running event that ends first (back to back, the one about to hand over).
    public var running: CalendarEvent? {
        timed.filter { $0.isRunning(at: now) }.min { $0.end < $1.end }
    }

    /// The next event to start after now.
    public var next: CalendarEvent? {
        timed.first { $0.start > now }
    }

    /// Running wins, except when the next event is inside its last 5 minutes: a long solo block ("Dave, 10 to 17")
    /// must not hide the call starting at 14:30.
    public var focus: Focus? {
        let next = self.next
        if let next, next.start.timeIntervalSince(now) <= Self.soonWindow { return .upcoming(next) }
        if let running { return .running(running) }
        if let next { return .upcoming(next) }
        return nil
    }

    /// The menubar item, or nil to hide it: shown while an event runs or another starts later today. Far out it
    /// is the start time alone ("13:30"); inside the title window, or the last 5 minutes when the title is off,
    /// the title and a countdown ("Design sync · in 42 min"). An event after midnight shows only inside that window.
    public var menubar: Menubar? {
        switch focus {
        case .running(let event):
            return Menubar(text: label(event, text.remaining(until: event.end, from: now)), tint: .live, eventID: event.id)
        case .upcoming(let event):
            let lead = event.start.timeIntervalSince(now)
            let tint: Tint = lead <= Self.soonWindow ? .soon : .plain
            if lead <= max(TimeInterval(settings.titleMinutes * 60), Self.soonWindow) {
                return Menubar(text: label(event, text.countdown(to: event.start, from: now)), tint: tint, eventID: event.id)
            }
            guard text.calendar.isDate(event.start, inSameDayAs: now) else { return nil }
            return Menubar(text: text.clock(event.start), tint: tint, eventID: event.id)
        case nil:
            return nil
        }
    }

    private func label(_ event: CalendarEvent, _ when: String) -> String {
        settings.titleMinutes > 0 ? "\(CalendarText.trimmed(event.title)) · \(when)" : when
    }

    /// The Tools row's status line and its tint: "Next: Design sync · 14:30", "Design sync · in 4 min",
    /// "Design sync · 23 min left", "Nothing else today".
    public var rowStatus: (text: String, tint: Tint) {
        switch focus {
        case .running(let event):
            return ("\(event.title) · \(text.remaining(until: event.end, from: now))", .live)
        case .upcoming(let event) where event.start.timeIntervalSince(now) <= Self.soonWindow:
            return ("\(event.title) · \(text.countdown(to: event.start, from: now))", .soon)
        case .upcoming(let event) where text.calendar.isDate(event.start, inSameDayAs: now):
            return ("Next: \(event.title) · \(text.clock(event.start))", .plain)
        default:
            return ("Nothing else today", .plain)
        }
    }

    /// Today's timed events for the Calendar view, past ones marked, the next one (or the running one) flagged.
    public var todayRows: [Row] {
        let cal = text.calendar
        let today = timed.filter { cal.isDate($0.start, inSameDayAs: now) || ($0.start < now && $0.end > now) }
        let highlighted: String? = {
            switch focus {
            case .running(let e), .upcoming(let e): return cal.isDate(e.start, inSameDayAs: now) || e.isRunning(at: now) ? e.id : nil
            case nil: return nil
            }
        }()
        return today.map { Row(event: $0, isPast: $0.end <= now, isNext: $0.id == highlighted) }
    }

    /// What ⌃⌘J opens: a joinable event that started up to 10 minutes ago and is still on (the latest to start),
    /// else the next joinable one starting within 15 minutes.
    public var joinTarget: CalendarEvent? {
        let joinable = timed.filter(\.joinable)
        let late = joinable.filter {
            $0.isRunning(at: now) && now.timeIntervalSince($0.start) <= Self.joinLateWindow
        }.max { $0.start < $1.start }
        if let late { return late }
        return joinable.first { $0.start > now && $0.start.timeIntervalSince(now) <= Self.joinAheadWindow }
    }
}
