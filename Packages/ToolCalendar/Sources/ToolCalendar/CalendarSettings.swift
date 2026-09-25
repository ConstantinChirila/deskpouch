import Foundation

/// Calendar options, persisted in UserDefaults under `calendar.*` like the other tools' settings. The join key
/// lives with the tool (`calendar.hotkey`), the pill's position with the pill (`calendar.pillOrigin.*`).
public struct CalendarSettings: Equatable, Sendable {
    /// How far ahead an event makes the menubar item appear.
    public var previewMinutes = 60
    /// Title and countdown in the menubar, or the countdown alone.
    public var showTitle = true
    /// The system or user alert sound played when a pill appears (`NSSound(named:)`); nil plays nothing.
    public var soundName: String? = CalendarSettings.defaultSound
    public static let defaultSound = "Glass"
    /// Calendars switched off in the Calendar view (`EKCalendar.calendarIdentifier`).
    public var hiddenCalendars: Set<String> = []

    public static let previewChoices = [15, 30, 60, 180]

    public init() {}

    enum Key {
        static let previewMinutes = "calendar.previewMinutes"
        static let showTitle = "calendar.showTitle"
        static let soundName = "calendar.soundName"
        /// Before the picker: an on/off switch. Read once so "off" carries over as None.
        static let legacySound = "calendar.sound"
        static let hiddenCalendars = "calendar.hiddenCalendars"
    }

    /// "1 hour before", for the popup.
    public static func previewLabel(_ minutes: Int) -> String {
        switch minutes {
        case 60: "1 hour before"
        case let m where m > 60 && m % 60 == 0: "\(m / 60) hours before"
        default: "\(minutes) min before"
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> CalendarSettings {
        var settings = CalendarSettings()
        if defaults.object(forKey: Key.previewMinutes) != nil {
            let stored = defaults.integer(forKey: Key.previewMinutes)
            if previewChoices.contains(stored) { settings.previewMinutes = stored }
        }
        if defaults.object(forKey: Key.showTitle) != nil { settings.showTitle = defaults.bool(forKey: Key.showTitle) }
        if let name = defaults.string(forKey: Key.soundName) {
            settings.soundName = name.isEmpty ? nil : name
        } else if defaults.object(forKey: Key.legacySound) != nil, !defaults.bool(forKey: Key.legacySound) {
            settings.soundName = nil
        }
        settings.hiddenCalendars = Set(defaults.stringArray(forKey: Key.hiddenCalendars) ?? [])
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(previewMinutes, forKey: Key.previewMinutes)
        defaults.set(showTitle, forKey: Key.showTitle)
        defaults.set(soundName ?? "", forKey: Key.soundName)
        defaults.set(hiddenCalendars.sorted(), forKey: Key.hiddenCalendars)
    }
}
