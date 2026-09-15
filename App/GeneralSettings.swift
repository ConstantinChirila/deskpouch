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
    /// Mirror of `SMAppService.mainApp.status`; refreshed by `refreshLaunchAtLogin()`.
    private(set) var launchAtLogin = false

    @ObservationIgnored private let defaults: UserDefaults

    enum Key {
        static let sounds = "general.sounds"
        static let menubarTimer = "general.menubarTimer"
        static let keepHistory = "general.keepHistory"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sounds = defaults.object(forKey: Key.sounds) == nil ? true : defaults.bool(forKey: Key.sounds)
        menubarTimer = defaults.object(forKey: Key.menubarTimer) == nil ? true : defaults.bool(forKey: Key.menubarTimer)
        keepHistory = defaults.object(forKey: Key.keepHistory) == nil ? true : defaults.bool(forKey: Key.keepHistory)
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
        refreshLaunchAtLogin()
    }
}

/// TCC grants as the General view shows them.
struct PermissionStatus: Equatable {
    var microphone = false
    var screenRecording = false
    var accessibility = false

    var allGranted: Bool { microphone && screenRecording && accessibility }

    /// "Mic · Screen · Accessibility" when all granted, otherwise the missing ones.
    var summary: String {
        if allGranted { return "Mic · Screen · Accessibility" }
        var missing: [String] = []
        if !microphone { missing.append("Mic") }
        if !screenRecording { missing.append("Screen") }
        if !accessibility { missing.append("Accessibility") }
        return missing.joined(separator: " · ") + " missing"
    }
}
