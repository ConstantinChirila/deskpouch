import Foundation
@testable import ToolCalendar

/// A London calendar and a Friday at 14:18, like the mocks.
enum Fixture {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        return cal
    }()

    static let text = CalendarText(calendar: calendar, locale: Locale(identifier: "en_GB"))

    /// 2026-09-25 at `h:m` London time, or another day of 2026.
    static func at(_ h: Int, _ m: Int, day: Int = 25, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m))!
    }

    static let now = at(14, 18)

    static let meetNotes = """
    Talk about the new onboarding.

    Join with Google Meet: https://meet.google.com/abc-defg-hij
    Or dial: +44 20 3873 7654 PIN: 123456#
    Learn more about Meet at: https://support.google.com/a/users/answer/9282720
    """

    static func event(
        _ title: String, _ start: Date, minutes: Int = 30, id: String? = nil, other: Bool = false,
        alarms: [Int] = [], notes: String? = nil, location: String? = nil, url: String? = nil,
        attendance: CalendarEvent.Attendance = .none, allDay: Bool = false, calendarID: String = "gmail",
        email: String? = "me@gmail.com"
    ) -> CalendarEvent {
        CalendarEvent(
            id: id ?? title, calendarID: calendarID, calendarTitle: "me@gmail.com", calendarColor: "#83d754",
            accountEmail: email, title: title, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: allDay, attendance: attendance, hasOtherPerson: other,
            alarmOffsets: alarms.map { TimeInterval($0 * 60) }, location: location, url: url, notes: notes
        )
    }
}
