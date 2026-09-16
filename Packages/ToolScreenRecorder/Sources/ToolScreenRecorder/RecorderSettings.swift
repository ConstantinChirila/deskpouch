import CoreGraphics
import Foundation

/// Recorder options. Persisted in UserDefaults under `screen.*`; the panel UI for them lands in milestone 5.
public struct RecorderSettings: Equatable, Sendable {
    public enum Quality: String, CaseIterable, Sendable {
        /// Scaled so a full-screen recording fits 1080p. Regions and windows use the same pixels-per-point.
        case high
        /// Native pixels (2x on Retina displays).
        case full

        public var label: String {
            switch self {
            case .high: "High, 1080p"
            case .full: "Full, native"
            }
        }

        /// Pixel rows a full-screen recording is fitted into; nil keeps native pixels.
        var maxPixelHeight: CGFloat? {
            switch self {
            case .high: 1080
            case .full: nil
            }
        }
    }

    public var quality: Quality = .high
    public var frameRate: Int = 60
    public var systemAudio = true
    public var microphone = false
    public var showsCursor = true
    /// Recordings stop themselves after this long. 0 disables the guard.
    public var maxMinutes: Int = 30

    public init() {}

    public static let frameRates = [30, 60]

    /// "1080p · 60 fps · system audio" style summary for the panel card.
    public var summary: String {
        var parts = [quality == .high ? "1080p" : "Native", "\(frameRate) fps"]
        if systemAudio { parts.append("system audio") }
        if microphone { parts.append("mic") }
        if !systemAudio && !microphone { parts.append("no audio") }
        return parts.joined(separator: " · ")
    }

    // MARK: Persistence

    enum Key {
        static let quality = "screen.quality"
        static let frameRate = "screen.fps"
        static let systemAudio = "screen.systemAudio"
        static let microphone = "screen.microphone"
        static let cursor = "screen.cursor"
        static let maxMinutes = "screen.maxMinutes"
    }

    public static func load(from defaults: UserDefaults = .standard) -> RecorderSettings {
        var settings = RecorderSettings()
        if let raw = defaults.string(forKey: Key.quality), let quality = Quality(rawValue: raw) {
            settings.quality = quality
        }
        if defaults.object(forKey: Key.frameRate) != nil, frameRates.contains(defaults.integer(forKey: Key.frameRate)) {
            settings.frameRate = defaults.integer(forKey: Key.frameRate)
        }
        if defaults.object(forKey: Key.systemAudio) != nil { settings.systemAudio = defaults.bool(forKey: Key.systemAudio) }
        if defaults.object(forKey: Key.microphone) != nil { settings.microphone = defaults.bool(forKey: Key.microphone) }
        if defaults.object(forKey: Key.cursor) != nil { settings.showsCursor = defaults.bool(forKey: Key.cursor) }
        if defaults.object(forKey: Key.maxMinutes) != nil { settings.maxMinutes = max(0, defaults.integer(forKey: Key.maxMinutes)) }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(quality.rawValue, forKey: Key.quality)
        defaults.set(frameRate, forKey: Key.frameRate)
        defaults.set(systemAudio, forKey: Key.systemAudio)
        defaults.set(microphone, forKey: Key.microphone)
        defaults.set(showsCursor, forKey: Key.cursor)
        defaults.set(maxMinutes, forKey: Key.maxMinutes)
    }
}
