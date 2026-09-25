import DeskpouchCore
import Foundation
import Observation
import ServiceManagement
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "general")

/// App-wide switches from the General view. Persisted in UserDefaults under `general.*`; launch at login lives
/// with the system (SMAppService) and is only mirrored here.
@MainActor
@Observable
final class GeneralSettings {
    /// Start and stop cues.
    var sounds: Bool { didSet { defaults.set(sounds, forKey: Key.sounds) } }
    /// Digits next to the menubar dot while recording.
    var menubarTimer: Bool { didSet { defaults.set(menubarTimer, forKey: Key.menubarTimer) } }
    /// Off means the pipeline never writes a history row, whatever the tools' chips say.
    var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: Key.keepHistory) } }
    /// Where the listening and recording pill floats.
    var pillPosition: PillPosition { didSet { defaults.set(pillPosition.rawValue, forKey: Key.pillPosition) } }
    /// Mirror of `SMAppService.mainApp.status`; refreshed by `refreshLaunchAtLogin()`.
    private(set) var launchAtLogin = false

    @ObservationIgnored private let defaults: UserDefaults

    enum Key {
        static let sounds = "general.sounds"
        static let menubarTimer = "general.menubarTimer"
        static let keepHistory = "general.keepHistory"
        static let pillPosition = "general.pillPosition"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sounds = defaults.object(forKey: Key.sounds) == nil ? true : defaults.bool(forKey: Key.sounds)
        menubarTimer = defaults.object(forKey: Key.menubarTimer) == nil ? true : defaults.bool(forKey: Key.menubarTimer)
        keepHistory = defaults.object(forKey: Key.keepHistory) == nil ? true : defaults.bool(forKey: Key.keepHistory)
        pillPosition = defaults.string(forKey: Key.pillPosition).flatMap(PillPosition.init(rawValue:)) ?? .top
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch at login \(enabled) failed: \(String(describing: error), privacy: .public)")
        }
        // Registered, but switched off by the user in Login Items: only they can switch it back on, there.
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshLaunchAtLogin()
    }
}

/// TCC grants as the General view shows them.
struct PermissionStatus: Equatable {
    var microphone = false
    var screenRecording = false
    var accessibility = false
    /// Calendars full access; nil while the Calendar tool is off (no line for it then).
    var calendars: Bool?

    var allGranted: Bool { microphone && screenRecording && accessibility && calendars != false }

    /// "Mic · Screen · Accessibility" when all granted, otherwise the missing ones.
    var summary: String {
        if allGranted { return calendars == true ? "Mic · Screen · Accessibility · Calendars" : "Mic · Screen · Accessibility" }
        var missing: [String] = []
        if !microphone { missing.append("Mic") }
        if !screenRecording { missing.append("Screen") }
        if !accessibility { missing.append("Accessibility") }
        if calendars == false { missing.append("Calendars") }
        return missing.joined(separator: " · ") + " missing"
    }
}
