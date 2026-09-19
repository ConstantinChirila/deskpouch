import Foundation
import Testing
@testable import DeskpouchGallery

struct GalleryDatePresetTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func boundsAreWholeDaysInTheUsersCalendar() {
        let now = Self.date(2026, 9, 19, hour: 15)
        #expect(GalleryDatePreset.any.start(now: now, calendar: Self.calendar) == nil)
        #expect(GalleryDatePreset.today.start(now: now, calendar: Self.calendar) == Self.date(2026, 9, 19))
        // Today and the six days before it.
        #expect(GalleryDatePreset.week.start(now: now, calendar: Self.calendar) == Self.date(2026, 9, 13))
        #expect(GalleryDatePreset.month.start(now: now, calendar: Self.calendar) == Self.date(2026, 8, 21))
        #expect(GalleryDatePreset.year.start(now: now, calendar: Self.calendar) == Self.date(2026, 1, 1))
    }

    @Test func aWeekAcrossTheClockChangeStillStartsAtMidnight() {
        // British Summer Time ends on 25 October 2026: that day has 25 hours.
        let now = Self.date(2026, 10, 28, hour: 9)
        #expect(GalleryDatePreset.week.start(now: now, calendar: Self.calendar) == Self.date(2026, 10, 22))
    }
}
