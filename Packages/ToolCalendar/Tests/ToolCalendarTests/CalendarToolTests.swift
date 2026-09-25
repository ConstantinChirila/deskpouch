import DeskpouchCore
import Foundation
import Testing
@testable import ToolCalendar

/// Stands in for EventKit: fixed events, and an access prompt the test answers when it wants.
@MainActor
final class FakeSource: CalendarSource {
    var access: SourceAccess = .granted
    var events: [CalendarEvent] = []
    var onChange: (@MainActor () -> Void)?
    var watching = false
    /// When set, `requestAccess` waits until `answer` is called, like the system prompt left on screen.
    var holdsPrompt = false
    private var pending: CheckedContinuation<SourceAccess, Never>?
    private(set) var prompted = false

    func requestAccess() async -> SourceAccess {
        prompted = true
        guard holdsPrompt else { return access }
        return await withCheckedContinuation { pending = $0 }
    }

    func answer(_ access: SourceAccess) {
        self.access = access
        pending?.resume(returning: access)
        pending = nil
    }

    func startWatching() { watching = true }
    func stopWatching() { watching = false }
    func nudge() {}
    func calendars() -> [CalendarInfo] { [] }
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        events.filter { $0.end > start && $0.start < end }
    }
}

@MainActor
final class NoPills: PillPresenter {
    var refreshes = 0
    func refresh() { refreshes += 1 }
    var windowNumber: Int? { nil }
    var frame: CGRect? { nil }
}

@MainActor
final class Clock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
struct CalendarToolTests {
    func freshDefaults() -> UserDefaults {
        let name = "CalendarToolTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Today relative to the real calendar the tool uses (`Calendar.current`), well clear of midnight.
    func today(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())!
    }

    struct Harness {
        let tool: CalendarTool
        let source: FakeSource
        let clock: Clock
        let opened: () -> [URL]
        let sounds: () -> Int
    }

    func make(defaults: UserDefaults, source: FakeSource = FakeSource(), at date: Date) -> Harness {
        let clock = Clock(date)
        var opened: [URL] = []
        var sounds = 0
        let tool = CalendarTool(
            model: CalendarModel(settings: CalendarSettings.load(from: defaults)), source: source, pills: NoPills(),
            defaults: defaults, now: { clock.date }, openURL: { opened.append($0) }, playSound: { _ in sounds += 1 }
        )
        return Harness(tool: tool, source: source, clock: clock, opened: { opened }, sounds: { sounds })
    }

    func call(at start: Date, alarms: [Int]) -> CalendarEvent {
        CalendarEvent(
            id: "sync", accountEmail: "me@gmail.com", title: "Design sync", start: start,
            end: start.addingTimeInterval(1800), hasOtherPerson: true,
            alarmOffsets: alarms.map { TimeInterval($0 * 60) }, notes: Fixture.meetNotes
        )
    }

    @Test func aFiredAlarmIsPersistedAndNotRepeatedAfterARelaunch() async {
        let defaults = freshDefaults()
        let start = today(12, 0)
        let source = FakeSource()
        source.events = [call(at: start, alarms: [5])]
        let first = make(defaults: defaults, source: source, at: today(11, 50))
        first.tool.activate()
        await first.tool.starting?.value
        #expect(first.tool.model.pills.pills.isEmpty)
        first.clock.date = today(11, 55)
        first.tool.tick()
        #expect(first.tool.model.pills.pills.map(\.id) == ["sync"])
        #expect(first.sounds() == 1)
        first.tool.deactivate()

        // A relaunch whose last check predates the alarm: only the persisted key stops a repeat.
        defaults.set(today(11, 50).timeIntervalSince1970, forKey: CalendarTool.lastCheckKey)
        let second = make(defaults: defaults, source: source, at: today(11, 56))
        second.tool.activate()
        await second.tool.starting?.value
        #expect(second.tool.model.pills.pills.isEmpty)
        #expect(second.sounds() == 0)
    }

    @Test func theLastCheckIsPersistedSoARelaunchDoesNotBackfill() async {
        let defaults = freshDefaults()
        let source = FakeSource()
        source.events = [call(at: today(12, 0), alarms: [5])]
        let first = make(defaults: defaults, source: source, at: today(11, 50))
        first.tool.activate()
        await first.tool.starting?.value
        first.tool.deactivate()
        #expect(defaults.double(forKey: CalendarTool.lastCheckKey) == today(11, 50).timeIntervalSince1970)
    }

    @Test func switchedOffWhileThePromptIsUpStaysStopped() async {
        let source = FakeSource()
        source.holdsPrompt = true
        let h = make(defaults: freshDefaults(), source: source, at: today(11, 0))
        h.tool.activate()
        for _ in 0..<200 where !source.prompted { await Task.yield() }
        h.tool.deactivate()
        source.answer(.granted)
        await h.tool.starting?.value
        #expect(!h.tool.running)
        #expect(!source.watching)
        #expect(h.tool.model.access == .unknown)
    }

    @Test func joinOpensTheCallDismissesItsPillAndSkipsLaterAlarms() async throws {
        let source = FakeSource()
        source.events = [call(at: today(12, 0), alarms: [15, 5])]
        let h = make(defaults: freshDefaults(), source: source, at: today(11, 40))
        h.tool.activate()
        await h.tool.starting?.value
        h.clock.date = today(11, 45)
        h.tool.tick()
        let pill = try #require(h.tool.model.pills.pills.first)
        h.tool.model.join(pill.event)
        #expect(h.opened().map(\.absoluteString) == ["https://meet.google.com/abc-defg-hij?authuser=me@gmail.com"])
        #expect(h.tool.model.pills.pills.isEmpty)
        h.clock.date = today(11, 55)
        h.tool.tick()
        #expect(h.tool.model.pills.pills.isEmpty)
        #expect(h.sounds() == 1)
    }

    @Test func theJoinKeyShowsAMessageWhenNoCallIsNear() async {
        let source = FakeSource()
        source.events = [call(at: today(15, 0), alarms: [])]
        let h = make(defaults: freshDefaults(), source: source, at: today(11, 0))
        h.tool.activate()
        await h.tool.starting?.value
        h.tool.keyPressed()
        #expect(h.opened().isEmpty)
        #expect(h.tool.model.message == "No call in the next 15 min")
    }
}
