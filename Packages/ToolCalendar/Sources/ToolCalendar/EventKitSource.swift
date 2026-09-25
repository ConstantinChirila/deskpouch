import AppKit
import EventKit
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "calendar")

/// One calendar as the Calendar view lists it.
public struct CalendarInfo: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var account: String
    public var color: String?
}

/// Calendars full access as the source reports it.
enum SourceAccess: Equatable, Sendable {
    case notDetermined, granted, denied
}

/// Where the calendar tool gets its events: EventKit in the app, a fake in the tests.
@MainActor
protocol CalendarSource: AnyObject {
    /// The current grant, without prompting.
    var access: SourceAccess { get }
    /// Prompts the first time; afterwards answers from the stored grant.
    func requestAccess() async -> SourceAccess
    /// Called whenever the calendar data changed.
    var onChange: (@MainActor () -> Void)? { get set }
    func startWatching()
    func stopWatching()
    /// Asks for a sync sooner than the account's own interval.
    func nudge()
    func calendars() -> [CalendarInfo]
    func events(from start: Date, to end: Date) -> [CalendarEvent]
}

/// Reads macOS Calendar through EventKit (plan 11: the Google account is added in Internet Accounts). Main actor
/// only: `EKEventStore` is not Sendable. The fetch is synchronous; its cost on a calendar with several shared and
/// holiday calendars is unmeasured, and the tool coalesces change bursts before calling it.
@MainActor
final class EventKitSource: CalendarSource {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    /// Called on the main actor whenever macOS reports a change to the calendar database.
    var onChange: (@MainActor () -> Void)?

    var access: SourceAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> SourceAccess {
        guard access == .notDetermined else { return access }
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .granted : .denied
        } catch {
            log.error("calendar access request failed: \(String(describing: error), privacy: .public)")
            return .denied
        }
    }

    func startWatching() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    func stopWatching() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Asks macOS to sync the accounts now rather than at their next interval. Whether Google-backed sources
    /// honour it is unmeasured (plan 11, step 0 skipped the lag test).
    func nudge() {
        store.refreshSourcesIfNecessary()
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, color: Self.hex($0.cgColor)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.convert)
    }

    static func convert(_ event: EKEvent) -> CalendarEvent {
        let attendees = event.attendees ?? []
        let me = attendees.first(where: \.isCurrentUser)
        let others = attendees.contains { !$0.isCurrentUser && $0.participantType != .room && $0.participantType != .resource }
        let organizerIsSomeoneElse = event.organizer.map { !$0.isCurrentUser } ?? false
        let start = event.startDate ?? Date()
        let offsets: [TimeInterval] = (event.alarms ?? []).map { alarm in
            if let absolute = alarm.absoluteDate { return start.timeIntervalSince(absolute) }
            return -alarm.relativeOffset
        }
        let occurrence = event.occurrenceDate ?? start
        return CalendarEvent(
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(Int(occurrence.timeIntervalSince1970))",
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            calendarColor: event.calendar.flatMap { hex($0.cgColor) },
            accountEmail: accountEmail(event, me: me),
            title: event.title ?? "",
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            attendance: attendance(me?.participantStatus),
            isCancelled: event.status == .canceled,
            hasOtherPerson: others || organizerIsSomeoneElse,
            alarmOffsets: offsets,
            location: event.location,
            url: event.url?.absoluteString,
            notes: event.notes
        )
    }

    /// Step 0: a Google source's title is the account's address; the primary calendar's title is too; failing
    /// both, my own attendee entry carries `mailto:<address>`.
    static func accountEmail(_ event: EKEvent, me: EKParticipant?) -> String? {
        if let title = event.calendar?.source?.title, title.contains("@") { return title }
        if let title = event.calendar?.title, title.contains("@") { return title }
        if let url = me?.url, url.scheme == "mailto" { return url.absoluteString.replacingOccurrences(of: "mailto:", with: "") }
        return nil
    }

    static func attendance(_ status: EKParticipantStatus?) -> CalendarEvent.Attendance {
        switch status {
        case nil: .none
        case .accepted?: .accepted
        case .declined?: .declined
        case .tentative?: .tentative
        default: .pending
        }
    }

    static func hex(_ color: CGColor?) -> String? {
        guard let color, let c = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
