import AppKit
import DeskpouchCore

/// Composition root. Owns hotkeys, overlay, status item and the menubar panel.
/// Tools plug in here from milestone 2 on.
@MainActor
final class Shell {
    let state = ShellState()
    private let hotkeys = HotkeyCenter()
    private let overlay = OverlayController()
    private let statusItem = StatusItemController()
    private lazy var panel = MenuPanelController(state: state, actions: panelActions)

    private var ticker: Timer?
    private var lastTick: Date?
    private var levelSource = SimulatedLevelSource()
    private var permissionPoll: Timer?

    init() {}

    func start() {
        hotkeys.registerHold(state.holdKey) { [weak self] phase in
            switch phase {
            case .pressed: self?.beginListening()
            case .released: self?.endListening()
            }
        }
        statusItem.onClick = { [weak self] button in
            self?.panel.toggle(relativeTo: button)
        }
        statusItem.showIdle()
        startHotkeysOrWait()
        runDemoIfRequested()
    }

    /// `DESKPOUCH_DEMO=pill` shows the listening state and the panel for a few seconds at launch.
    /// With `DESKPOUCH_DEMO_OUT=<dir>` it also writes PNGs of both. Design review only.
    private func runDemoIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["DESKPOUCH_DEMO"] == "pill" else { return }
        let out = env["DESKPOUCH_DEMO_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            beginListening()
            if let button = statusItem.button { panel.open(relativeTo: button) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let out else { return }
            Self.writePNG(overlay.debugSnapshot(), to: out.appending(path: "app-pill.png"))
            Self.writePNG(panel.debugSnapshot(), to: out.appending(path: "app-panel.png"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.endListening()
            self?.panel.close()
        }
    }

    private static func writePNG(_ image: NSImage?, to url: URL) {
        guard let image, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            NSLog("deskpouch demo: could not encode %@", url.lastPathComponent)
            return
        }
        do { try png.write(to: url) } catch { NSLog("deskpouch demo: write failed %@", "\(error)") }
    }

    func stop() {
        endListening()
        hotkeys.stop()
        permissionPoll?.invalidate()
    }

    // MARK: Hotkey permission

    private func startHotkeysOrWait() {
        if hotkeys.start() {
            state.hotkeyReady = true
            permissionPoll?.invalidate()
            permissionPoll = nil
            return
        }
        state.hotkeyReady = false
        guard permissionPoll == nil else { return }
        // First failure: show the system Accessibility prompt so the hold key can work at all.
        Permissions.requestAccessibility()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.startHotkeysOrWait() }
        }
    }

    private var panelActions: MenuPanelActions {
        MenuPanelActions(
            requestPermission: { [weak self] in
                guard let self else { return }
                if !Permissions.accessibilityGranted {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                } else {
                    // Accessibility is on but the tap still failed: fall back to Input Monitoring.
                    Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                }
                startHotkeysOrWait()
            },
            quit: { NSApp.terminate(nil) }
        )
    }

    // MARK: Listening

    private func beginListening() {
        guard !state.isListening else { return }
        state.isListening = true
        levelSource = SimulatedLevelSource()
        overlay.showListening()
        statusItem.beginListening()
        lastTick = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    private func endListening() {
        guard state.isListening else { return }
        state.isListening = false
        ticker?.invalidate()
        ticker = nil
        overlay.hide()
        statusItem.showIdle()
    }

    private func tick() {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 1 / 30
        lastTick = now
        let level = levelSource.next()
        overlay.push(level: level, dt: dt)
        statusItem.push(level: level, dt: dt)
    }
}
