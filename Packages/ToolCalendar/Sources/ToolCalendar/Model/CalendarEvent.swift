import Foundation

/// One occurrence of a calendar event, copied out of EventKit so everything after the source is plain values.
public struct CalendarEvent: Sendable, Equatable, Identifiable {
    /// My answer to the invitation. `none` when the event has no attendees (made by me, or a solo reminder).
    public enum Attendance: Sendable, Equatable {
        case none, pending, accepted, tentative, declined
    }

    /// Stable per occurrence: the event identifier plus the original occurrence date (`EKEvent.occurrenceDate`
    /// stays put when one occurrence of a series is moved).
    public var id: String
    public var calendarID: String
    public var calendarTitle: String
    /// "#83d754", for the colour dot.
    public var calendarColor: String?
    /// The address of the account the calendar belongs to, for Meet's `authuser` (step 0: the Google source's
    /// title is the address).
    public var accountEmail: String?
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var attendance: Attendance
    public var isCancelled: Bool
    /// Someone other than me is on it, as organizer or attendee. EventKit leaves the organizer out of `attendees`
    /// when someone else invited me (step 0), so the source checks both.
    public var hasOtherPerson: Bool
    /// Seconds before the start, positive, as the calendar's alarms say (duplicates and days-long offsets
    /// included; `Reminders` merges them).
    public var alarmOffsets: [TimeInterval]
    // Constant, so the link found in them at init stays right.
    public let location: String?
    public let url: String?
    public let notes: String?
    /// The call link found in url, location and notes, resolved once: finding it runs a data detector and HTML
    /// stripping, and the pill and agenda read it on every render.
    public let link: URL?

    public init(
        id: String, calendarID: String = "cal", calendarTitle: String = "Calendar", calendarColor: String? = nil,
        accountEmail: String? = nil, title: String, start: Date, end: Date, isAllDay: Bool = false,
        attendance: Attendance = .none, isCancelled: Bool = false, hasOtherPerson: Bool = false,
        alarmOffsets: [TimeInterval] = [], location: String? = nil, url: String? = nil, notes: String? = nil
    ) {
        self.id = id
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.accountEmail = accountEmail
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.attendance = attendance
        self.isCancelled = isCancelled
        self.hasOtherPerson = hasOtherPerson
        self.alarmOffsets = alarmOffsets
        self.location = location
        self.url = url
        self.notes = notes
        link = MeetingLink.find(url: url, location: location, notes: notes)
    }

    /// The link Join opens, when there is one worth joining: a call link on an event with another person on it.
    /// Google adds a Meet link to every event its user creates, so a solo event's link is ignored.
    public var joinLink: URL? {
        guard hasOtherPerson else { return nil }
        return link?.withAuthUser(accountEmail)
    }

    public var joinable: Bool { joinLink != nil }

    public var isMeet: Bool { joinLink?.host == MeetingLink.meetHost }

    /// "Grand Central Kitchen" rather than the whole address, for one line.
    public var shortLocation: String? {
        guard let location, !location.isEmpty, !location.contains("://") else { return nil }
        return location.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public func isRunning(at now: Date) -> Bool {
        start <= now && now < end
    }
}
