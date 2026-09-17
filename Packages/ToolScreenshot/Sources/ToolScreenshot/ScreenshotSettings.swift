import DeskpouchCapture
import Foundation

/// Screenshot options. Persisted in UserDefaults under `shot.*`, same pattern as the recorder's `RecorderSettings`.
/// The save folder is not kept here: like the recorder, it lives in the tool's `ToolOutputConfig.folder` (the
/// pipeline's `saveToFolder` action reads that directly), so there is one source of truth for where a capture
/// lands instead of two settings that could drift apart.
public struct ScreenshotSettings: Equatable, Sendable {
    /// Output resolution: native pixels (2x on a Retina display, the default) or downsampled to one pixel per
    /// point. See `CaptureScale`.
    public var scale: CaptureScale = .native
    /// Window captures keep the macOS drop shadow, drawn on a transparent background.
    public var windowShadow = true

    public init() {}

    enum Key {
        static let scale = "shot.scale"
        static let windowShadow = "shot.windowShadow"
    }

    public static func load(from defaults: UserDefaults = .standard) -> ScreenshotSettings {
        var settings = ScreenshotSettings()
        if let raw = defaults.string(forKey: Key.scale), let scale = CaptureScale(rawValue: raw) {
            settings.scale = scale
        }
        if defaults.object(forKey: Key.windowShadow) != nil {
            settings.windowShadow = defaults.bool(forKey: Key.windowShadow)
        }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(scale.rawValue, forKey: Key.scale)
        defaults.set(windowShadow, forKey: Key.windowShadow)
    }
}
