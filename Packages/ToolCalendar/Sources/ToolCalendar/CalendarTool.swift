import AppKit
import Carbon.HIToolbox
import DeskpouchCore
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "calendar")

/// What draws the pills: the real window in the app, nothing in the tests.
@MainActor
protocol PillPresenter: AnyObject {
    /// Shows, resizes or hides the window to match the model.
    func refresh()
    var windowNumber: Int? { get }
    var frame: CGRect? { get }
}

/// Plan 11: the next event in the menubar, today's agenda in the panel, a pill at each of an event's alarms,
/// and ⌃⌘J to join the call. Reads macOS Calendar through EventKit. Emits no results and writes no history.
@MainActor
public final class CalendarTool: Tool {
    public let id = "calendar"
    public let name = "Calendar"
    public var pressKey: KeyCombo? {
        didSet {
            let data = pressKey.flatMap { try? JSONEncoder().encode($0) }
            defaults.set(data, forKey: Self.hotkeyDefaultsKey)
        }
    }
    static let hotkeyDefaultsKey = "calendar.hotkey"
    public static let defaultKey = KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.control, .command])
    public var defaultOutput: ToolOutputConfig { ToolOutputConfig(actions: []) }

    public let model: CalendarModel
    /// The menubar item's text and tint, nil to hide it. The shell draws it.
    public var onMenubar: (@MainActor (Agenda.Menubar?) -> Void)?
    /// A pill's body was clicked: open the panel on the Calendar view.
    public var onOpenPanel: (@MainActor () -> Void)?

    private let source: any CalendarSource
    private let pillWindow: any PillPresenter
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private let openURL: @MainActor (URL) -> Void
    private let playSound: @MainActor (String?) -> Void
    private var events: [CalendarEvent] = []
    private var reminders: Reminders
    private var lastCheck: Date
    private var ticker: Timer?
    private var refetcher: Timer?
    private var expiryCheck: Task<Void, Never>?
    private var messageHide: Task<Void, Never>?
    private var changeCoalescer: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var fetchedDay: Date?
    /// Switched on in General. `start` rechecks it after the access prompt: the switch can go off while the
    /// prompt is up, and a tool switched off must not start running when the prompt is answered.
    private var wanted = false
    private(set) var running = false
    /// The pending `start`, so tests can await it.
    private(set) var starting: Task<Void, Never>?
    /// Set by the demo: fixture events stay put, nothing is fetched or ticked.
    private var frozen = false

    static let firedKey = "calendar.firedAlarms"
    static let lastCheckKey = "calendar.lastCheck"
    /// Alarms of 6 days ahead are common on the step 0 calendar; 8 days covers them.
    static let lookAhead: TimeInterval = 8 * 24 * 3600
    /// EventKit posts changes in bursts while an account syncs; one refetch per burst.
    static let changeCoalescing: Duration = .milliseconds(300)

    public convenience init(defaults: UserDefaults = .standard) {
        let settings = CalendarSettings.load(from: defaults)
        let model = CalendarModel(settings: settings)
        self.init(
            model: model, source: EventKitSource(), pills: CalendarPillController(model: model, defaults: defaults),
            defaults: defaults, now: { Date() }, openURL: { NSWorkspace.shared.open($0) },
            playSound: { CalendarSounds.play($0) }
        )
    }

    init(
        model: CalendarModel, source: any CalendarSource, pills: any PillPresenter, defaults: UserDefaults,
        now: @escaping @MainActor () -> Date, openURL: @escaping @MainActor (URL) -> Void,
        playSound: @escaping @MainActor (String?) -> Void
    ) {
        self.model = model
        self.source = source
        pillWindow = pills
        self.defaults = defaults
        self.now = now
        self.openURL = openURL
        self.playSound = playSound
        model.sounds = CalendarSounds.available()
        let stored = (defaults.dictionary(forKey: Self.firedKey) as? [String: Double]) ?? [:]
        reminders = Reminders(fired: stored.mapValues { Date(timeIntervalSince1970: $0) })
        let last = defaults.double(forKey: Self.lastCheckKey)
        lastCheck = last > 0 ? Date(timeIntervalSince1970: last) : now()
        if let data = defaults.data(forKey: Self.hotkeyDefaultsKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            pressKey = combo
        } else {
            pressKey = Self.defaultKey
        }
        model.joinHandler = { [weak self] event in self?.join(event) }
        model.updateHandler = { [weak self] change in self?.updateSettings(change) }
        model.retryAccessHandler = { [weak self] in self?.retryAccess() }
        model.pillHandler = { [weak self] action in self?.pillAction(action) }
    }

    public func attach(_ context: ToolContext) {}

    public func activate() {
        wanted = true
        starting = Task { await start() }
    }

    public func deactivate() {
        wanted = false
        stop()
        model.access = .unknown
    }

    public func keyPressed() {
        if let target = model.agenda.joinTarget {
            join(target)
        } else {
            showMessage("No call in the next 15 min")
        }
    }

    // MARK: Lifecycle

    private func start() async {
        let access = await source.requestAccess()
        // The prompt can stay up for a long time; the switch may have gone off meanwhile.
        guard wanted else { return }
        model.access = access == .granted ? .granted : .denied
        guard access == .granted, !running else {
            if access != .granted { log.info("calendar access not granted") }
            return
        }
        running = true
        source.onChange = { [weak self] in self?.sourceChanged() }
        source.startWatching()
        refetch()
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 1
        refetcher = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.source.nudge()
                self?.refetch()
            }
        }
        refetcher?.tolerance = 10
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.source.nudge()
                self?.refetch()
            }
        }
    }

    private func stop() {
        running = false
        source.stopWatching()
        source.onChange = nil
        ticker?.invalidate()
        refetcher?.invalidate()
        ticker = nil
        refetcher = nil
        expiryCheck?.cancel()
        changeCoalescer?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        events = []
        model.pills = PillStack()
        model.agenda = Agenda(events: [], now: now(), settings: model.settings)
        pillWindow.refresh()
        onMenubar?(nil)
    }

    private func retryAccess() {
        if source.access == .notDetermined {
            wanted = true
            starting = Task { await start() }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            openURL(url)
        }
    }

    /// The panel opened: the grant may have changed in System Settings meanwhile.
    public func panelOpened() {
        model.sounds = CalendarSounds.available()
        let access = source.access
        if access == .granted, !running, wanted {
            starting = Task { await start() }
        } else if access != .granted, running {
            stop()
            model.access = .denied
        }
        if running {
            source.nudge()
            refetch()
        }
    }

    // MARK: Data

    /// One refetch per burst of change notifications.
    private func sourceChanged() {
        changeCoalescer?.cancel()
        changeCoalescer = Task { [weak self] in
            try? await Task.sleep(for: Self.changeCoalescing)
            guard !Task.isCancelled else { return }
            self?.refetch()
        }
    }

    private func refetch() {
        guard running, !frozen else { return }
        let now = now()
        let startOfDay = Calendar.current.startOfDay(for: now)
        events = source.events(from: startOfDay, to: now.addingTimeInterval(Self.lookAhead))
        model.calendars = source.calendars()
        fetchedDay = startOfDay
        tick()
    }

    /// Rebuilds the agenda, fires due alarms, expires pills, updates the menubar. Every 5 s and after each fetch.
    func tick() {
        guard running, !frozen else { return }
        let now = now()
        if let fetchedDay, !Calendar.current.isDate(fetchedDay, inSameDayAs: now) {
            refetch()
            return
        }
        let agenda = Agenda(events: events, now: now, settings: model.settings)
        model.agenda = agenda
        let fired = reminders.due(events: agenda.timed, since: lastCheck, now: now, calendar: .current)
        var stack = model.pills
        for fire in fired { stack.show(fire, now: now) }
        stack.update(now: now, events: agenda.timed)
        if stack != model.pills { model.pills = stack }
        if !fired.isEmpty {
            log.info("calendar pills: \(fired.count)")
            playSound(model.settings.soundName)
            reminders.prune(now: now)
            defaults.set(reminders.fired.mapValues(\.timeIntervalSince1970), forKey: Self.firedKey)
        }
        lastCheck = now
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastCheckKey)
        onMenubar?(agenda.menubar)
        pillWindow.refresh()
        scheduleExpiryCheck()
    }

    /// Heads-ups live 8 s; the 5 s ticker alone would keep one up to 13 s.
    private func scheduleExpiryCheck() {
        expiryCheck?.cancel()
        guard let next = model.pills.pills.compactMap(\.expiresAt).min() else { return }
        let delay = max(0.05, next.timeIntervalSince(now()) + 0.05)
        expiryCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            var stack = model.pills
            stack.update(now: now(), events: model.agenda.timed)
            if stack != model.pills {
                model.pills = stack
                pillWindow.refresh()
            }
            scheduleExpiryCheck()
        }
    }

    private func updateSettings(_ change: (inout CalendarSettings) -> Void) {
        var settings = model.settings
        change(&settings)
        guard settings != model.settings else { return }
        settings.save(to: defaults)
        model.settings = settings
        tick()
    }

    // MARK: Actions

    /// Opens the call and retires the event's pills. Only http(s) links are opened: whatever a calendar invite
    /// carries must never launch an app, mount a share or reach another app's URL handler from a Join button.
    private func join(_ event: CalendarEvent) {
        guard let link = event.joinLink, let scheme = link.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return
        }
        log.info("joining \(link.host ?? "?", privacy: .public)")
        openURL(link)
        reminders.markJoined(event.id)
        var stack = model.pills
        stack.dismiss(event.id)
        model.pills = stack
        pillWindow.refresh()
    }

    private func pillAction(_ action: CalendarModel.PillAction) {
        var stack = model.pills
        switch action {
        case .dismiss(let id): stack.dismiss(id)
        case .hold(let id): stack.hold(id)
        case .release(let id): stack.release(id, now: now())
        case .open:
            onOpenPanel?()
            return
        case .moved:
            return
        }
        model.pills = stack
        pillWindow.refresh()
        scheduleExpiryCheck()
    }

    private func showMessage(_ text: String) {
        model.message = text
        pillWindow.refresh()
        messageHide?.cancel()
        messageHide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            model.message = nil
            pillWindow.refresh()
        }
    }

    // MARK: Demo

    /// Debug demo: replaces the source with fixed events and fires one pill of each kind.
    public func debugLoad(events: [CalendarEvent], pills fires: [Reminders.Fire]) {
        wanted = true
        running = true
        frozen = true
        model.access = .granted
        self.events = events
        let now = now()
        model.agenda = Agenda(events: events, now: now, settings: model.settings)
        var stack = PillStack()
        for fire in fires { stack.show(fire, now: now) }
        model.pills = stack
        onMenubar?(model.agenda.menubar)
        pillWindow.refresh()
    }

    public func debugMessage(_ text: String) {
        showMessage(text)
    }

    /// The pill window, for the demo's snapshot; nil while no pill shows.
    public var debugPillWindowNumber: Int? {
        pillWindow.windowNumber
    }

    public var debugPillFrame: CGRect? { pillWindow.frame }
}
