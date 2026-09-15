import Foundation
import Testing
@testable import DeskpouchCore

struct DayGroupTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // Tuesday 15 September 2026, 10:00 UTC.
    let now = Date(timeIntervalSince1970: 1_789_466_400)

    @Test func labels() {
        #expect(DayGroup.label(for: now, now: now, calendar: calendar) == "Today")
        #expect(DayGroup.label(for: now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "Yesterday")
        #expect(DayGroup.label(for: now.addingTimeInterval(-7 * 86_400), now: now, calendar: calendar) == "Tue 8 Sep")
        #expect(DayGroup.label(for: now.addingTimeInterval(-400 * 86_400), now: now, calendar: calendar) == "Mon 11 Aug 2025")
    }

    @Test func sectionsSplitOnDayChangesAndKeepOrder() {
        let dates = [now, now.addingTimeInterval(-3600), now.addingTimeInterval(-86_400), now.addingTimeInterval(-9 * 86_400)]
        let sections = DayGroup.sections(dates, date: { $0 }, now: now, calendar: calendar)
        #expect(sections.map(\.label) == ["Today", "Yesterday", "Sun 6 Sep"])
        #expect(sections[0].items.count == 2)
    }
}
