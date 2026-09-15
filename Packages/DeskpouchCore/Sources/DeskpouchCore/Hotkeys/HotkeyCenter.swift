import AppKit
import CoreGraphics
import os

let hotkeyLog = Logger(subsystem: "com.constantinchirila.deskpouch", category: "hotkeys")

/// Global hotkeys. Modifier holds go through AppKit event monitors (Accessibility access needed; without it the
/// monitors receive nothing). Key combos go through Carbon hotkeys, which need no grant and swallow the key press.
@MainActor
public final class HotkeyCenter {
    public typealias HoldHandler = @MainActor (HotkeyPhase) -> Void

    public final class Registration {
        fileprivate var detector: ModifierHoldDetector
        fileprivate let handler: HoldHandler
        fileprivate init(detector: ModifierHoldDetector, handler: @escaping HoldHandler) {
            self.detector = detector
            self.handler = handler
        }
    }

    private var holds: [Registration] = []
    private var presses: [UInt32] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init() {}

    public var isRunning: Bool { globalMonitor != nil }

    /// Registers a hold-to-act modifier key. Two registrations for the same key both fire.
    @discardableResult
    public func registerHold(_ key: ModifierKey, handler: @escaping HoldHandler) -> Registration {
        let registration = Registration(detector: ModifierHoldDetector(key: key), handler: handler)
        holds.append(registration)
        return registration
    }

    public func unregister(_ registration: Registration) {
        holds.removeAll { $0 === registration }
    }

    /// Registers a press-to-act combo. Works without `start()`. Returns false when another app owns the combo.
    @discardableResult
    public func registerPress(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) -> Bool {
        guard let id = CarbonHotkeys.shared.register(combo, handler: handler) else { return false }
        presses.append(id)
        return true
    }

    /// Installs the monitors. Returns false when the process is not trusted for Accessibility.
    @discardableResult
    public func start() -> Bool {
        if isRunning { return true }
        let trusted = Permissions.accessibilityGranted
        hotkeyLog.info("start: accessibility=\(trusted) inputMonitoring=\(Permissions.inputMonitoringGranted)")
        guard trusted else { return false }
        // Global monitors see other apps' events; the local one covers events while Deskpouch itself is active.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        hotkeyLog.info("monitors installed")
        return true
    }

    public func stop() {
        for id in presses { CarbonHotkeys.shared.unregister(id) }
        presses.removeAll()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        for registration in holds {
            registration.detector = ModifierHoldDetector(key: registration.detector.key)
        }
    }

    private func handle(_ event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.cgEvent?.flags ?? CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        hotkeyLog.debug("flagsChanged keyCode=\(keyCode) flags=0x\(String(flags.rawValue, radix: 16), privacy: .public)")
        for registration in holds {
            if let phase = registration.detector.handle(keyCode: keyCode, flags: flags) {
                hotkeyLog.info("\(registration.detector.key.displayName, privacy: .public) \(String(describing: phase), privacy: .public)")
                registration.handler(phase)
            }
        }
    }
}
