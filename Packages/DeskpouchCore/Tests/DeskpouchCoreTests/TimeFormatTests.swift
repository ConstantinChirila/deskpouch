import Testing
@testable import DeskpouchCore

struct TimeFormatTests {
    @Test func formats() {
        #expect(TimeFormat.minutesSeconds(0) == "0:00")
        #expect(TimeFormat.minutesSeconds(4.9) == "0:04")
        #expect(TimeFormat.minutesSeconds(72) == "1:12")
        #expect(TimeFormat.minutesSeconds(725) == "12:05")
        #expect(TimeFormat.minutesSeconds(-3) == "0:00")
    }
}
