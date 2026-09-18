import Foundation

/// Colour picker options, persisted in UserDefaults under `color.*` like the other tools' settings.
public struct ColorSettings: Equatable, Sendable {
    public var format: ColorFormat = .hex
    /// Name the nearest Tailwind v4 entry in the loupe.
    public var tailwindHints = true

    public init() {}

    enum Key {
        static let format = "color.format"
        static let tailwindHints = "color.tailwindHints"
    }

    /// "Hex · Tailwind hints", for the panel row.
    public var summary: String {
        tailwindHints ? "\(format.label) · Tailwind hints" : format.label
    }

    public static func load(from defaults: UserDefaults = .standard) -> ColorSettings {
        var settings = ColorSettings()
        if let raw = defaults.string(forKey: Key.format), let format = ColorFormat(rawValue: raw) {
            settings.format = format
        }
        if defaults.object(forKey: Key.tailwindHints) != nil {
            settings.tailwindHints = defaults.bool(forKey: Key.tailwindHints)
        }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(format.rawValue, forKey: Key.format)
        defaults.set(tailwindHints, forKey: Key.tailwindHints)
    }
}
