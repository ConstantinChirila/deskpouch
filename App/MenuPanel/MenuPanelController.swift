import AppKit
import DeskpouchCore
import SwiftUI
import ToolScreenRecorder

struct MenuPanelActions {
    var requestPermission: @MainActor () -> Void
    var toggleOutput: @MainActor (_ toolID: String, _ action: OutputAction) -> Void
    var copyRecent: @MainActor (HistoryItem) -> Void
    var revealRecent: @MainActor (HistoryItem) -> Void
    var setHoldKey: @MainActor (ModifierKey) -> Void
    var setPressKey: @MainActor (KeyCombo) -> Void
    var setVoiceLanguage: @MainActor (String) -> Void
    var setVoiceMicrophone: @MainActor (String?) -> Void
    var updateRecorder: @MainActor ((inout RecorderSettings) -> Void) -> Void
    var chooseFolder: @MainActor () -> Void
    var setLaunchAtLogin: @MainActor (Bool) -> Void
    var clearHistory: @MainActor () -> Void
    var openPermissionSettings: @MainActor () -> Void
    var closePanel: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

/// The one panel that is the whole app. Drops from the status item, closes on click outside or Escape.
@MainActor
final class MenuPanelController {
    private let panel: NSPanel
    private let hosting: NSHostingView<MenuPanelView>
    private let state: ShellState
    private var resignObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var closing: Task<Void, Never>?

    static let width: CGFloat = 400
    /// Room around the panel for its shadow.
    static let shadowInset = NSEdgeInsets(top: 20, left: 60, bottom: 90, right: 60)
    /// Set while a file chooser is up, so losing key status does not close the panel.
    var holdsOpen = false

    init(state: ShellState, actions: MenuPanelActions) {
        self.state = state
        hosting = NSHostingView(rootView: MenuPanelView(state: state, actions: actions))
        // The window spans from the status item to the bottom of the screen; the content is top-aligned inside
        // and free to grow (expanded cards, General) without the window resizing.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]

        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.contentView = hosting

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.holdsOpen else { return }
                self.close()
            }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton) {
        if state.panelPresented { close() } else { open(relativeTo: button) }
    }

    func open(relativeTo button: NSStatusBarButton) {
        closing?.cancel()
        closing = nil
        let inset = Self.shadowInset
        let anchor = button.window?.convertToScreen(button.bounds) ?? .zero
        let screen = button.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Window top sits `inset.top` above the visible panel; the panel's top edge lands 4pt under the status item.
        let top = anchor.minY - 4 + inset.top
        let content = CGSize(width: Self.width + inset.left + inset.right, height: max(200, top - visible.minY - 8))
        panel.setContentSize(content)
        hosting.frame = CGRect(origin: .zero, size: content)
        var origin = CGPoint(x: anchor.midX - content.width / 2, y: top - content.height)
        let maxX = visible.maxX - content.width + inset.right - 8
        let minX = visible.minX - inset.left + 8
        origin.x = min(max(origin.x, minX), maxX)
        panel.setFrameOrigin(origin)

        panel.alphaValue = 1
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        state.panelPresented = true
    }

    /// Screenshot of the live panel window. Design review only.
    func debugSnapshot() async -> NSImage? {
        await WindowSnapshot.capture(windowNumber: panel.windowNumber)
    }

    /// Fades out over 120 ms, then takes the window off screen.
    func close() {
        guard panel.isVisible, closing == nil else { return }
        removeKeyMonitor()
        state.panelPresented = false
        state.popups.close()
        state.confirmingClear = false
        closing = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            panel.orderOut(nil)
            closing = nil
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event } // Escape
            if state.popups.isOpen {
                state.popups.close()
            } else if state.confirmingClear {
                state.confirmingClear = false
            } else if state.panelView == .general {
                state.panelView = .main
            } else {
                close()
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// Borderless panels refuse key status by default; this one takes it so Escape and ⌘Q work.
@MainActor
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
