import AppKit
import DeskpouchCore
import SwiftUI

struct MenuPanelActions {
    var requestPermission: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

/// The one panel that is the whole app. Drops from the status item, closes on click outside or Escape.
@MainActor
final class MenuPanelController {
    private let panel: NSPanel
    private let hosting: NSHostingView<MenuPanelView>
    private var resignObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    static let width: CGFloat = 400
    /// Room around the panel for its shadow.
    static let shadowInset = NSEdgeInsets(top: 20, left: 60, bottom: 90, right: 60)

    init(state: ShellState, actions: MenuPanelActions) {
        hosting = NSHostingView(rootView: MenuPanelView(state: state, actions: actions))
        hosting.sizingOptions = [.intrinsicContentSize]

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
            MainActor.assumeIsolated { self?.close() }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isVisible { close() } else { open(relativeTo: button) }
    }

    func open(relativeTo button: NSStatusBarButton) {
        hosting.layoutSubtreeIfNeeded()
        let content = hosting.fittingSize
        panel.setContentSize(content)

        let inset = Self.shadowInset
        let anchor = button.window?.convertToScreen(button.bounds) ?? .zero
        let screen = button.window?.screen ?? NSScreen.main
        // Window top sits `inset.top` above the visible panel; the panel's top edge lands 4pt under the status item.
        var origin = CGPoint(
            x: anchor.midX - content.width / 2,
            y: anchor.minY - 4 + inset.top - content.height
        )
        if let visible = screen?.visibleFrame {
            let maxX = visible.maxX - content.width + inset.right - 8
            let minX = visible.minX - inset.left + 8
            origin.x = min(max(origin.x, minX), maxX)
        }
        panel.setFrameOrigin(origin)

        panel.alphaValue = 1
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func debugSnapshot() -> NSImage? {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func close() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.close()
                return nil
            }
            return event
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
