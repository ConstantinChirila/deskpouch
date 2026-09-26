import Foundation
import Testing
@testable import ToolCalendar

struct RemindersTests {
    let cal = Fixture.calendar

    /// Runs `due` once over (since, now].
    func fires(_ events: [CalendarEvent], since: Date, now: Date, reminders: inout Reminders) -> [Reminders.Fire] {
        reminders.due(events: events, since: since, now: now, calendar: cal)
    }

    @Test func noAlarmsNoPill() {
        var r = Reminders()
        let e = Fixture.event("Design sync", Fixture.at(14, 30))
        #expect(fires([e], since: Fixture.at(14, 0), now: Fixture.at(14, 31), reminders: &r).isEmpty)
    }

    @Test func stickyAtEachAlarmAndAtTheStart() {
        var r = Reminders()
        let e = Fixture.event("Design sync", Fixture.at(14, 30), alarms: [15, 5])
        var seen: [Date] = []
        var t = Fixture.at(14, 0)
        while t < Fixture.at(14, 40) {
            let next = t.addingTimeInterval(30)
            for fire in fires([e], since: t, now: next, reminders: &r) {
                #expect(fire.kind == .sticky)
                seen.append(fire.at)
            }
            t = next
        }
        #expect(seen == [Fixture.at(14, 15), Fixture.at(14, 25), Fixture.at(14, 30)])
    }

    @Test func duplicateOffsetsAreMerged() {
        var r = Reminders()
        let e = Fixture.event("Flu jab", Fixture.at(14, 30), alarms: [10, 10, 10, 10])
        let first = fires([e], since: Fixture.at(14, 19), now: Fixture.at(14, 20), reminders: &r)
        #expect(first.count == 1)
        #expect(fires([e], since: Fixture.at(14, 20), now: Fixture.at(14, 21), reminders: &r).isEmpty)
    }

    @Test func laterDayIsAHeadsUp() {
        var r = Reminders()
        let e = Fixture.event("Dermato", Fixture.at(13, 30, day: 26), alarms: [1440])
        let got = fires([e], since: Fixture.at(13, 29), now: Fixture.at(13, 30), reminders: &r)
        #expect(got.map(\.kind) == [.headsUp])
    }

    @Test func refetchWithoutChangeDoesNotRepeatButMovingRearms() {
        var r = Reminders()
        var e = Fixture.event("Design sync", Fixture.at(14, 30), alarms: [5])
        #expect(fires([e], since: Fixture.at(14, 20), now: Fixture.at(14, 26), reminders: &r).count == 1)
        #expect(fires([e], since: Fixture.at(14, 20), now: Fixture.at(14, 26), reminders: &r).isEmpty)
        e.start = Fixture.at(14, 45)
        e.end = Fixture.at(15, 15)
        #expect(fires([e], since: Fixture.at(14, 39), now: Fixture.at(14, 40), reminders: &r).count == 1)
    }

    @Test func missedStickyFiresWithinFiveMinutesOnlyTheLatest() {
        var r = Reminders()
        let e = Fixture.event("Design sync", Fixture.at(14, 30), alarms: [15, 5])
        // Asleep from 14:00 to 14:28: the 14:15 and 14:25 alarms were missed; 14:25 is within grace.
        let got = fires([e], since: Fixture.at(14, 0), now: Fixture.at(14, 28), reminders: &r)
        #expect(got.map(\.at) == [Fixture.at(14, 25)])
        // Asleep until 14:37: the start alarm (14:30) is 7 minutes old, too late.
        var r2 = Reminders()
        #expect(fires([e], since: Fixture.at(14, 0), now: Fixture.at(14, 37), reminders: &r2).isEmpty)
    }

    @Test func missedHeadsUpShowsOnceOnWakeWhileTheEventIsAhead() {
        var r = Reminders()
        let show = Fixture.event("NEC show", Fixture.at(10, 0, day: 3, month: 10), minutes: 360, alarms: [8640, 1440])
        let got = fires([show], since: Fixture.at(9, 0, day: 26), now: Fixture.at(12, 0, day: 27), reminders: &r)
        #expect(got.count == 1)
        #expect(got.first?.kind == .headsUp)
        #expect(fires([show], since: Fixture.at(12, 0, day: 27), now: Fixture.at(12, 1, day: 27), reminders: &r).isEmpty)
    }

    @Test func joinedEventsSkipLaterAlarms() {
        var r = Reminders()
        let e = Fixture.event("Design sync", Fixture.at(14, 30), alarms: [15, 5])
        #expect(fires([e], since: Fixture.at(14, 14), now: Fixture.at(14, 15), reminders: &r).count == 1)
        r.markJoined(e.id)
        #expect(fires([e], since: Fixture.at(14, 15), now: Fixture.at(14, 31), reminders: &r).isEmpty)
    }

    @Test func endedEventsFireNothingAndPruneForgetsOldKeys() {
        var r = Reminders()
        let e = Fixture.event("Short", Fixture.at(14, 0), minutes: 5, alarms: [0])
        #expect(fires([e], since: Fixture.at(13, 0), now: Fixture.at(14, 6), reminders: &r).isEmpty)
        let f = Fixture.event("Later", Fixture.at(15, 0), alarms: [5])
        _ = fires([f], since: Fixture.at(14, 54), now: Fixture.at(14, 55), reminders: &r)
        #expect(!r.fired.isEmpty)
        r.prune(now: Fixture.at(15, 0, day: 5, month: 10))
        #expect(r.fired.isEmpty)
    }
}

struct PillStackTests {
    func fire(_ e: CalendarEvent, _ kind: Reminders.Kind = .sticky) -> Reminders.Fire {
        Reminders.Fire(event: e, kind: kind, at: Fixture.now)
    }

    @Test func laterAlarmReplacesTheEarlierPillAndNewestIsFirst() {
        var stack = PillStack()
        let a = Fixture.event("A", Fixture.at(14, 30))
        let b = Fixture.event("B", Fixture.at(14, 45))
        stack.show(fire(a), now: Fixture.now)
        stack.show(fire(b), now: Fixture.now)
        stack.show(fire(a), now: Fixture.now)
        #expect(stack.pills.map(\.id) == ["A", "B"])
    }

    @Test func capsAtThree() {
        var stack = PillStack()
        for name in ["A", "B", "C", "D"] {
            stack.show(fire(Fixture.event(name, Fixture.at(15, 0))), now: Fixture.now)
        }
        #expect(stack.pills.map(\.id) == ["D", "C", "B"])
    }

    @Test func stickyClearsAtTheEndOrWhenTheEventStopsCounting() {
        var stack = PillStack()
        let a = Fixture.event("A", Fixture.at(14, 30))
        stack.show(fire(a), now: Fixture.now)
        stack.update(now: Fixture.at(14, 59), events: [a])
        #expect(stack.pills.count == 1)
        stack.update(now: Fixture.at(15, 0), events: [a])
        #expect(stack.pills.isEmpty)
        stack.show(fire(a), now: Fixture.now)
        stack.update(now: Fixture.now, events: [])
        #expect(stack.pills.isEmpty)
    }

    @Test func stickyPicksUpEdits() {
        var stack = PillStack()
        var a = Fixture.event("A", Fixture.at(14, 30))
        stack.show(fire(a), now: Fixture.now)
        a.title = "A, renamed"
        stack.update(now: Fixture.now, events: [a])
        #expect(stack.pills.first?.event.title == "A, renamed")
    }

    @Test func headsUpLivesEightSecondsAndHoverHoldsIt() {
        var stack = PillStack()
        let d = Fixture.event("Dermato", Fixture.at(13, 30, day: 26))
        stack.show(fire(d, .headsUp), now: Fixture.now)
        stack.update(now: Fixture.now.addingTimeInterval(7), events: [])
        #expect(stack.pills.count == 1)
        stack.hold(d.id)
        stack.update(now: Fixture.now.addingTimeInterval(30), events: [])
        #expect(stack.pills.count == 1)
        stack.release(d.id, now: Fixture.now.addingTimeInterval(30))
        stack.update(now: Fixture.now.addingTimeInterval(33), events: [])
        #expect(stack.pills.isEmpty)
    }

    @Test func subtitles() {
        let t = Fixture.text
        let call = Fixture.event("Design sync", Fixture.at(14, 30), other: true, notes: Fixture.meetNotes)
        let pill = PillStack.Pill(event: call, kind: .sticky, expiresAt: nil)
        #expect(PillStack.subtitle(pill, now: Fixture.at(14, 25), text: t) == "in 5 min · Meet")
        #expect(PillStack.subtitle(pill, now: Fixture.at(14, 30), text: t) == "starting now · Meet")
        #expect(PillStack.subtitle(pill, now: Fixture.at(14, 34), text: t) == "started 4 min ago · Meet")
        let dinner = Fixture.event("Dinner", Fixture.at(18, 0), other: true, location: "Grand Central Kitchen, Birmingham")
        #expect(PillStack.subtitle(.init(event: dinner, kind: .sticky, expiresAt: nil), now: Fixture.at(17, 50), text: t) == "in 10 min · Grand Central Kitchen")
        let tomorrow = Fixture.event("Dermato", Fixture.at(13, 30, day: 26))
        #expect(PillStack.subtitle(.init(event: tomorrow, kind: .headsUp, expiresAt: nil), now: Fixture.now, text: t) == "tomorrow 13:30")
        let saturdayWeek = Fixture.event("NEC", Fixture.at(10, 0, day: 3, month: 10))
        #expect(PillStack.subtitle(.init(event: saturdayWeek, kind: .headsUp, expiresAt: nil), now: Fixture.now, text: t) == "Sat 3 Oct")
        let within = Fixture.event("Party", Fixture.at(19, 0, day: 29))
        #expect(PillStack.subtitle(.init(event: within, kind: .headsUp, expiresAt: nil), now: Fixture.now, text: t) == "Tue 19:00")
    }
}

struct CalendarSettingsTests {
    @Test func roundTripAndBadValues() throws {
        let defaults = try #require(UserDefaults(suiteName: "calendar-settings-test"))
        defaults.removePersistentDomain(forName: "calendar-settings-test")
        var s = CalendarSettings()
        s.titleMinutes = 30
        s.soundName = "Ping"
        s.hiddenCalendars = ["b", "a"]
        s.save(to: defaults)
        #expect(CalendarSettings.load(from: defaults) == s)
        s.titleMinutes = 0
        s.save(to: defaults)
        #expect(CalendarSettings.load(from: defaults).titleMinutes == 0)
        defaults.set(7, forKey: CalendarSettings.Key.titleMinutes)
        #expect(CalendarSettings.load(from: defaults).titleMinutes == 60)
        s.soundName = nil
        s.save(to: defaults)
        #expect(CalendarSettings.load(from: defaults).soundName == nil)
        #expect(CalendarSettings.titleLabel(60) == "1 hour before")
        #expect(CalendarSettings.titleLabel(180) == "3 hours before")
        #expect(CalendarSettings.titleLabel(15) == "15 min before")
        #expect(CalendarSettings.titleLabel(0) == "Never")
    }

    @Test func legacyPreviewWindowAndTitleSwitchCarryOver() throws {
        let defaults = try #require(UserDefaults(suiteName: "calendar-settings-legacy-title"))
        defaults.removePersistentDomain(forName: "calendar-settings-legacy-title")
        defaults.set(180, forKey: CalendarSettings.Key.legacyPreviewMinutes)
        defaults.set(true, forKey: CalendarSettings.Key.legacyShowTitle)
        #expect(CalendarSettings.load(from: defaults).titleMinutes == 180)
        defaults.set(false, forKey: CalendarSettings.Key.legacyShowTitle)
        #expect(CalendarSettings.load(from: defaults).titleMinutes == 0)
        var s = CalendarSettings.load(from: defaults)
        s.titleMinutes = 30
        s.save(to: defaults)
        #expect(CalendarSettings.load(from: defaults).titleMinutes == 30)
    }

    @Test func legacySoundSwitchCarriesOver() throws {
        let defaults = try #require(UserDefaults(suiteName: "calendar-settings-legacy"))
        defaults.removePersistentDomain(forName: "calendar-settings-legacy")
        #expect(CalendarSettings.load(from: defaults).soundName == "Glass")
        defaults.set(false, forKey: CalendarSettings.Key.legacySound)
        #expect(CalendarSettings.load(from: defaults).soundName == nil)
        defaults.set(true, forKey: CalendarSettings.Key.legacySound)
        #expect(CalendarSettings.load(from: defaults).soundName == "Glass")
    }

    @Test func systemSoundsAreListed() {
        let names = CalendarSounds.names(in: URL(fileURLWithPath: "/System/Library/Sounds"))
        #expect(names.contains("Glass"))
        #expect(!names.contains { $0.hasSuffix(".aiff") })
    }
}
