import Foundation
import Testing
@testable import ToolCalendar

struct AgendaTests {
    func agenda(_ events: [CalendarEvent], now: Date = Fixture.now, settings: CalendarSettings = CalendarSettings()) -> Agenda {
        Agenda(events: events, now: now, settings: settings, text: Fixture.text)
    }

    @Test func soloEventsCountForTheMenubar() {
        let a = agenda([Fixture.event("Clean coffee machine", Fixture.at(14, 40))])
        #expect(a.menubar == Agenda.Menubar(text: "Clean coffee machine · in 22 min", tint: .plain, eventID: "Clean coffee machine"))
    }

    @Test func declinedCancelledHiddenAndAllDayDoNotCount() {
        var cancelled = Fixture.event("Cancelled", Fixture.at(14, 30))
        cancelled.isCancelled = true
        var settings = CalendarSettings()
        settings.hiddenCalendars = ["family"]
        let a = agenda([
            Fixture.event("Declined", Fixture.at(14, 25), attendance: .declined),
            cancelled,
            Fixture.event("Family thing", Fixture.at(14, 26), calendarID: "family"),
            Fixture.event("Holiday", Fixture.at(0, 0), minutes: 24 * 60, allDay: true),
        ], settings: settings)
        #expect(a.menubar == nil)
        #expect(a.todayRows.isEmpty)
        #expect(a.allDayToday.map(\.title) == ["Holiday"])
    }

    @Test func hiddenOutsideThePreviewWindow() {
        let later = Fixture.event("Standup", Fixture.at(15, 30))
        #expect(agenda([later]).menubar == nil)
        var settings = CalendarSettings()
        settings.previewMinutes = 180
        #expect(agenda([later], settings: settings).menubar?.text == "Standup · in 1 h 12 min")
    }

    @Test func tintTurnsAmberInTheLastFiveMinutesAndMintWhileRunning() {
        let e = Fixture.event("Design sync", Fixture.at(14, 30))
        #expect(agenda([e], now: Fixture.at(14, 24)).menubar?.tint == .plain)
        #expect(agenda([e], now: Fixture.at(14, 25)).menubar?.tint == .soon)
        #expect(agenda([e], now: Fixture.at(14, 25)).menubar?.text == "Design sync · in 5 min")
        let live = agenda([e], now: Fixture.at(14, 37)).menubar
        #expect(live == Agenda.Menubar(text: "Design sync · 23 min left", tint: .live, eventID: "Design sync"))
        #expect(agenda([e], now: Fixture.at(15, 0)).menubar == nil)
    }

    @Test func handsOverAtTheEndAndTheNextWinsInItsLastFiveMinutes() {
        let a = Fixture.event("A", Fixture.at(14, 0), minutes: 60)
        let b = Fixture.event("B", Fixture.at(15, 0))
        #expect(agenda([a, b], now: Fixture.at(14, 50)).menubar?.text == "A · 10 min left")
        #expect(agenda([a, b], now: Fixture.at(14, 55)).menubar?.text == "B · in 5 min")
        #expect(agenda([a, b], now: Fixture.at(15, 0)).menubar?.text == "B · 30 min left")
    }

    @Test func aLongBlockDoesNotHideACallAboutToStart() {
        let block = Fixture.event("Dave", Fixture.at(10, 0), minutes: 7 * 60)
        let call = Fixture.event("Design sync", Fixture.at(14, 30), other: true)
        #expect(agenda([block, call]).menubar?.text == "Dave · 2 h 42 min left")
        #expect(agenda([block, call], now: Fixture.at(14, 26)).menubar?.text == "Design sync · in 4 min")
    }

    @Test func titleOffAndTrimming() {
        var settings = CalendarSettings()
        settings.showTitle = false
        let e = Fixture.event("Quarterly planning with the whole design team", Fixture.at(14, 30))
        #expect(agenda([e], settings: settings).menubar?.text == "in 12 min")
        #expect(agenda([e]).menubar?.text == "Quarterly planning… · in 12 min")
        #expect(CalendarText.trimmed("Quarterly planning with") == "Quarterly planning…")
    }

    @Test func rowStatus() {
        let e = Fixture.event("Design sync", Fixture.at(14, 30))
        #expect(agenda([e], now: Fixture.at(10, 0)).rowStatus.text == "Next: Design sync · 14:30")
        #expect(agenda([e], now: Fixture.at(14, 26)).rowStatus == ("Design sync · in 4 min", .soon))
        #expect(agenda([e], now: Fixture.at(14, 37)).rowStatus == ("Design sync · 23 min left", .live))
        #expect(agenda([e], now: Fixture.at(16, 0)).rowStatus.text == "Nothing else today")
        let tomorrow = Fixture.event("Dermato", Fixture.at(13, 30, day: 26))
        #expect(agenda([tomorrow]).rowStatus.text == "Nothing else today")
    }

    @Test func todayRowsMarkPastAndNext() {
        let rows = agenda([
            Fixture.event("Bin day!", Fixture.at(8, 30), minutes: 5),
            Fixture.event("Design sync", Fixture.at(14, 30)),
            Fixture.event("Dinner", Fixture.at(18, 0), minutes: 90),
            Fixture.event("Tomorrow", Fixture.at(9, 0, day: 26)),
        ]).todayRows
        #expect(rows.map(\.event.title) == ["Bin day!", "Design sync", "Dinner"])
        #expect(rows.map(\.isPast) == [true, false, false])
        #expect(rows.map(\.isNext) == [false, true, false])
    }

    @Test func joinTargetLateThenAheadThenNone() {
        let call = Fixture.event("Design sync", Fixture.at(14, 30), other: true, notes: Fixture.meetNotes)
        let solo = Fixture.event("Bin day!", Fixture.at(14, 20), notes: Fixture.meetNotes)
        #expect(agenda([call, solo], now: Fixture.at(14, 15)).joinTarget?.title == "Design sync")
        #expect(agenda([call, solo], now: Fixture.at(14, 14)).joinTarget == nil)
        #expect(agenda([call, solo], now: Fixture.at(14, 40)).joinTarget?.title == "Design sync")
        #expect(agenda([call, solo], now: Fixture.at(14, 41)).joinTarget == nil)
    }

    @Test func lateJoinPrefersTheRunningCallOverTheNextOne() {
        let running = Fixture.event("A", Fixture.at(14, 10), other: true, notes: Fixture.meetNotes)
        let next = Fixture.event("B", Fixture.at(14, 25), other: true, notes: Fixture.meetNotes)
        #expect(agenda([running, next]).joinTarget?.title == "A")
    }
}
