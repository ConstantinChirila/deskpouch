import Foundation
import Observation

/// What the panel, the menubar item and the pills read. Written by `CalendarTool`; the views call back through
/// the methods at the bottom, which forward to the tool.
@MainActor
@Observable
public final class CalendarModel {
    public enum Access: Sendable, Equatable {
        /// Switched off, or not asked yet.
        case unknown
        case granted
        /// Refused in the prompt or later in System Settings.
        case denied
    }

    public internal(set) var access: Access = .unknown
    public internal(set) var agenda: Agenda
    public internal(set) var calendars: [CalendarInfo] = []
    public internal(set) var pills = PillStack()
    public internal(set) var settings: CalendarSettings
    /// A one-line message pill ("No call in the next 15 min"), shown for a few seconds.
    public internal(set) var message: String?
    /// Alert sounds for the picker; reread each time the panel opens.
    public internal(set) var sounds: [String] = []

    @ObservationIgnored var joinHandler: (@MainActor (CalendarEvent) -> Void)?
    @ObservationIgnored var updateHandler: (@MainActor ((inout CalendarSettings) -> Void) -> Void)?
    @ObservationIgnored var retryAccessHandler: (@MainActor () -> Void)?
    @ObservationIgnored var pillHandler: (@MainActor (PillAction) -> Void)?

    enum PillAction {
        case dismiss(String)
        case hold(String)
        case release(String)
        case open
        case moved
    }

    init(settings: CalendarSettings) {
        self.settings = settings
        agenda = Agenda(events: [], now: Date(), settings: settings)
    }

    public func join(_ event: CalendarEvent) { joinHandler?(event) }
    /// Picks the pill sound and plays it once, so the choice is heard. nil is None.
    public func chooseSound(_ name: String?) {
        update { $0.soundName = name }
        CalendarSounds.play(name)
    }
    public func update(_ change: (inout CalendarSettings) -> Void) { updateHandler?(change) }
    public func setCalendar(_ id: String, visible: Bool) {
        update { settings in
            if visible { settings.hiddenCalendars.remove(id) } else { settings.hiddenCalendars.insert(id) }
        }
    }
    /// Asks again when never asked, otherwise opens System Settings › Privacy & Security › Calendars.
    public func retryAccess() { retryAccessHandler?() }
}
