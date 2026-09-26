import Foundation

/// Calendar options, persisted in UserDefaults under `calendar.*` like the other tools' settings. The join key
/// lives with the tool (`calendar.hotkey`), the pill's position with the pill (`calendar.pillOrigin.*`).
public struct CalendarSettings: Equatable, Sendable {
    /// How far ahead of an event the menubar item names it and counts down ("Design sync · in 42 min"); before
    /// that it shows the start time alone. 0 never shows the title.
    public var titleMinutes = 60
    /// The system or user alert sound played when a pill appears (`NSSound(named:)`); nil plays nothing.
    public var soundName: String? = CalendarSettings.defaultSound
    public static let defaultSound = "Glass"
    /// Calendars switched off in the Calendar view (`EKCalendar.calendarIdentifier`).
    public var hiddenCalendars: Set<String> = []

    /// 0 is "Never", last in the popup.
    public static let titleChoices = [15, 30, 60, 180, 0]

    public init() {}

    enum Key {
        static let titleMinutes = "calendar.titleMinutes"
        /// Before "Show title" became a popup: a preview window that hid the item, and an on/off title switch.
        /// Read once so both carry over.
        static let legacyPreviewMinutes = "calendar.previewMinutes"
        static let legacyShowTitle = "calendar.showTitle"
        static let soundName = "calendar.soundName"
        /// Before the picker: an on/off switch. Read once so "off" carries over as None.
        static let legacySound = "calendar.sound"
        static let hiddenCalendars = "calendar.hiddenCalendars"
    }

    /// "1 hour before", "Never", for the popup.
    public static func titleLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Never"
        case 60: "1 hour before"
        case let m where m > 60 && m % 60 == 0: "\(m / 60) hours before"
        default: "\(minutes) min before"
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> CalendarSettings {
        var settings = CalendarSettings()
        if defaults.object(forKey: Key.titleMinutes) != nil {
            let stored = defaults.integer(forKey: Key.titleMinutes)
            if titleChoices.contains(stored) { settings.titleMinutes = stored }
        } else if defaults.object(forKey: Key.legacyShowTitle) != nil, !defaults.bool(forKey: Key.legacyShowTitle) {
            settings.titleMinutes = 0
        } else if defaults.object(forKey: Key.legacyPreviewMinutes) != nil {
            let stored = defaults.integer(forKey: Key.legacyPreviewMinutes)
            if titleChoices.contains(stored), stored > 0 { settings.titleMinutes = stored }
        }
        if let name = defaults.string(forKey: Key.soundName) {
            settings.soundName = name.isEmpty ? nil : name
        } else if defaults.object(forKey: Key.legacySound) != nil, !defaults.bool(forKey: Key.legacySound) {
            settings.soundName = nil
        }
        settings.hiddenCalendars = Set(defaults.stringArray(forKey: Key.hiddenCalendars) ?? [])
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(titleMinutes, forKey: Key.titleMinutes)
        defaults.set(soundName ?? "", forKey: Key.soundName)
        defaults.set(hiddenCalendars.sorted(), forKey: Key.hiddenCalendars)
    }
}
