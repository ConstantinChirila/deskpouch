import Foundation

/// Decides when a calendar pill appears (plan 11, "Pill alert"). Only events with alarms get pills: one at each
/// alarm (offsets merged) and one at the start. Sticky for an event today, an 8 s heads-up for a later day.
/// Pure and value typed; the tool keeps one, persists `fired` so a relaunch does not repeat a pill, and calls
/// `due` every few seconds with the time it last called it.
public struct Reminders: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The event is today: stays until ×, Join, or the event's end.
        case sticky
        /// The event is on a later day: shows for a few seconds.
        case headsUp
    }

    public struct Fire: Sendable, Equatable {
        public var event: CalendarEvent
        public var kind: Kind
        public var at: Date

        public init(event: CalendarEvent, kind: Kind, at: Date) {
            self.event = event
            self.kind = kind
            self.at = at
        }
    }

    /// A sticky alarm the Mac slept through still fires this long after its time.
    static let stickyGrace: TimeInterval = 5 * 60
    /// Fired keys are kept this long, then pruned. Longer than any gap worth backfilling.
    static let memory: TimeInterval = 8 * 24 * 3600

    /// Alarm key -> the alarm's time. The key holds the event's start, so moving an event re-arms its alarms and
    /// an unchanged refetch does not repeat them.
    public private(set) var fired: [String: Date]
    /// Events joined through any route: their later alarms are skipped.
    public private(set) var joined: Set<String> = []

    public init(fired: [String: Date] = [:]) {
        self.fired = fired
    }

    static func key(_ event: CalendarEvent, offset: TimeInterval) -> String {
        "\(event.id)|\(Int(offset))|\(Int(event.start.timeIntervalSince1970))"
    }

    /// Pills due between `since` (exclusive, the last call) and `now` (inclusive), at most one per event: when
    /// several alarms of one event fall in the window (the Mac slept through them), only the latest shows.
    /// `events` should already be filtered to the ones that count (the agenda's `timed`).
    public mutating func due(events: [CalendarEvent], since: Date, now: Date, calendar: Calendar) -> [Fire] {
        var result: [Fire] = []
        for event in events where !event.isAllDay && !event.alarmOffsets.isEmpty && !joined.contains(event.id) {
            guard now < event.end else { continue }
            let offsets = Set(event.alarmOffsets.filter { $0 >= 0 }.map { $0.rounded() }).union([0])
            var latest: Fire?
            for offset in offsets {
                let at = event.start.addingTimeInterval(-offset)
                guard at > since, at <= now else { continue }
                let key = Self.key(event, offset: offset)
                guard fired[key] == nil else { continue }
                fired[key] = at
                let kind: Kind = calendar.isDate(event.start, inSameDayAs: now) ? .sticky : .headsUp
                switch kind {
                case .sticky: guard now.timeIntervalSince(at) <= Self.stickyGrace else { continue }
                case .headsUp: guard event.start > now else { continue }
                }
                if latest.map({ at > $0.at }) ?? true {
                    latest = Fire(event: event, kind: kind, at: at)
                }
            }
            if let latest { result.append(latest) }
        }
        return result.sorted { $0.at < $1.at }
    }

    public mutating func markJoined(_ eventID: String) {
        joined.insert(eventID)
    }

    /// Drops keys older than `memory`, so the persisted set stays small.
    public mutating func prune(now: Date) {
        fired = fired.filter { now.timeIntervalSince($0.value) < Self.memory }
    }
}

/// The calendar pills on screen, newest first, at most three (plan 11: stacked from the anchor). Pure; the
/// overlay draws it.
public struct PillStack: Sendable, Equatable {
    public struct Pill: Sendable, Equatable, Identifiable {
        public var event: CalendarEvent
        public var kind: Reminders.Kind
        /// A heads-up's hide time; nil while held (hover) and always nil for a sticky pill.
        public var expiresAt: Date?
        public var id: String { event.id }
    }

    static let cap = 3
    static let headsUpLife: TimeInterval = 8
    /// After the pointer leaves a held heads-up.
    static let afterHover: TimeInterval = 3

    public private(set) var pills: [Pill] = []

    public init() {}

    /// A later alarm replaces the earlier pill of the same event; the newest goes nearest the anchor.
    public mutating func show(_ fire: Reminders.Fire, now: Date) {
        pills.removeAll { $0.id == fire.event.id }
        let expiry = fire.kind == .headsUp ? now.addingTimeInterval(Self.headsUpLife) : nil
        pills.insert(Pill(event: fire.event, kind: fire.kind, expiresAt: expiry), at: 0)
        if pills.count > Self.cap { pills.removeLast(pills.count - Self.cap) }
    }

    public mutating func dismiss(_ eventID: String) {
        pills.removeAll { $0.id == eventID }
    }

    public mutating func hold(_ eventID: String) {
        guard let i = pills.firstIndex(where: { $0.id == eventID }), pills[i].kind == .headsUp else { return }
        pills[i].expiresAt = nil
    }

    public mutating func release(_ eventID: String, now: Date) {
        guard let i = pills.firstIndex(where: { $0.id == eventID }), pills[i].kind == .headsUp else { return }
        pills[i].expiresAt = now.addingTimeInterval(Self.afterHover)
    }

    /// Drops heads-ups past their time and sticky pills whose event ended or no longer counts (deleted,
    /// cancelled, declined, calendar switched off: absent from `events`). Sticky pills pick up edits (title,
    /// time) from `events`.
    public mutating func update(now: Date, events: [CalendarEvent]) {
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        pills = pills.compactMap { pill in
            switch pill.kind {
            case .headsUp:
                if let expiry = pill.expiresAt, expiry <= now { return nil }
                return pill
            case .sticky:
                guard let fresh = byID[pill.id], now < fresh.end else { return nil }
                var pill = pill
                pill.event = fresh
                return pill
            }
        }
    }

    /// Line 2 of a pill: "in 5 min · Meet", "starting now · Room 3B", "started 4 min ago", "tomorrow 13:30".
    public static func subtitle(_ pill: Pill, now: Date, text: CalendarText) -> String {
        let when: String
        switch pill.kind {
        case .headsUp:
            when = text.laterDay(pill.event.start, isAllDay: pill.event.isAllDay, from: now)
        case .sticky:
            let since = now.timeIntervalSince(pill.event.start)
            if since < 0 {
                when = text.countdown(to: pill.event.start, from: now)
            } else if since < 60 {
                when = "starting now"
            } else {
                when = "started \(Int(since / 60)) min ago"
            }
        }
        if pill.event.isMeet { return when + " · Meet" }
        if let place = pill.event.shortLocation { return when + " · " + place }
        return when
    }
}
