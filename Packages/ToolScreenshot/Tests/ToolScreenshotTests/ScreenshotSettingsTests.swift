import DeskpouchCapture
import Foundation
import Testing
@testable import ToolScreenshot

struct ScreenshotSettingsTests {
    func freshDefaults() -> UserDefaults {
        let name = "ScreenshotSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsAreNativeScaleWithTheWindowShadowOn() {
        let settings = ScreenshotSettings.load(from: freshDefaults())
        #expect(settings.scale == .native)
        #expect(settings.windowShadow)
    }

    @Test func saveAndLoadRoundTrip() {
        let defaults = freshDefaults()
        var settings = ScreenshotSettings.load(from: defaults)
        settings.scale = .x1
        settings.windowShadow = false
        settings.save(to: defaults)

        let reloaded = ScreenshotSettings.load(from: defaults)
        #expect(reloaded.scale == .x1)
        #expect(!reloaded.windowShadow)
    }

    @Test func loadIgnoresAnUnknownStoredScale() {
        let defaults = freshDefaults()
        defaults.set("huge", forKey: ScreenshotSettings.Key.scale)
        let settings = ScreenshotSettings.load(from: defaults)
        #expect(settings.scale == .native)
    }
}
