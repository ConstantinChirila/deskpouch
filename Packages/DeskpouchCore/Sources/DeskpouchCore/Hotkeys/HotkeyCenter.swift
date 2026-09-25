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

    /// A press combo as the caller registered it. `carbonID` is nil while `stop()` has it out of the system.
    private struct Press {
        let combo: KeyCombo
        let handler: @MainActor () -> Void
        var carbonID: UInt32?
    }

    /// How often a held key is checked against the real modifier state.
    static let reconcileInterval: TimeInterval = 0.5

    private var holds: [Registration] = []
    private var presses: [UInt32: Press] = [:]
    private var nextPressID: UInt32 = 1
    private let carbon: any PressHotkeys
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var reconcileTimer: Timer?

    public init() {
        carbon = CarbonHotkeys.shared
    }

    init(carbon: any PressHotkeys) {
        self.carbon = carbon
    }

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
        updateReconcileTimer()
    }

    public struct PressRegistration {
        fileprivate let id: UInt32
    }

    /// Registers a press-to-act combo. Works without `start()`. Returns nil when another app owns the combo.
    @discardableResult
    public func registerPress(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) -> PressRegistration? {
        guard let carbonID = carbon.register(combo, handler: handler) else { return nil }
        let id = nextPressID
        nextPressID += 1
        presses[id] = Press(combo: combo, handler: handler, carbonID: carbonID)
        return PressRegistration(id: id)
    }

    public func unregister(_ registration: PressRegistration) {
        if let carbonID = presses.removeValue(forKey: registration.id)?.carbonID { carbon.unregister(carbonID) }
    }

    /// Installs the monitors and puts back the press combos `stop()` took out; their registrations stay valid.
    /// Returns false when the process is not trusted for Accessibility.
    @discardableResult
    public func start() -> Bool {
        restorePresses()
        if isRunning { return true }
        let trusted = Permissions.accessibilityGranted
        hotkeyLog.info("start: accessibility=\(trusted) inputMonitoring=\(Permissions.inputMonitoringGranted)")
        guard trusted else { return false }
        // Global monitors see other apps' events; the local one covers events while Deskpouch itself is active.
        // Key downs are watched too, so a modifier used in a chord (Option + e) does not count as a hold.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        hotkeyLog.info("monitors installed")
        return true
    }

    public func stop() {
        for (id, press) in presses {
            if let carbonID = press.carbonID { carbon.unregister(carbonID) }
            presses[id]?.carbonID = nil
        }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        for registration in holds {
            registration.detector = ModifierHoldDetector(key: registration.detector.key)
        }
        updateReconcileTimer()
    }

    /// A combo another app took in the meantime stays out and is tried again on the next `start()`.
    private func restorePresses() {
        for (id, press) in presses where press.carbonID == nil {
            presses[id]?.carbonID = carbon.register(press.combo, handler: press.handler)
        }
    }

    /// Runs the timer only while a hold is down.
    private func updateReconcileTimer() {
        let anyDown = holds.contains { $0.detector.isDown }
        if anyDown, reconcileTimer == nil {
            let timer = Timer(timeInterval: Self.reconcileInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reconcile(flags: CGEventSource.flagsState(.combinedSessionState))
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            reconcileTimer = timer
        } else if !anyDown {
            reconcileTimer?.invalidate()
            reconcileTimer = nil
        }
    }

    /// A release that never arrived as an event (Secure Input) is delivered from the real modifier state.
    func reconcile(flags: CGEventFlags) {
        for registration in holds {
            if let phase = registration.detector.reconcile(flagStillDown: flags.contains(registration.detector.key.flag)) {
                hotkeyLog.info("\(registration.detector.key.displayName, privacy: .public) \(String(describing: phase), privacy: .public) by reconcile")
                registration.handler(phase)
            }
        }
        updateReconcileTimer()
    }

    private func handle(_ event: NSEvent) {
        defer { updateReconcileTimer() }
        if event.type == .keyDown {
            for registration in holds {
                if let phase = registration.detector.handleKeyDown() {
                    hotkeyLog.info("\(registration.detector.key.displayName, privacy: .public) \(String(describing: phase), privacy: .public) by a key press")
                    registration.handler(phase)
                }
            }
            return
        }
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
