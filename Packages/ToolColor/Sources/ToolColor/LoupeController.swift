import AppKit
import DeskpouchCore
import SwiftUI
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "color")

/// One interactive `OverlayWindow` per screen showing the loupe, the cursor hidden. Mouse moves steer it, arrows
/// nudge it a pixel (Shift: ten), a click or Return picks, Escape or a right click cancels.
@MainActor
final class LoupeController {
    let model: LoupeModel
    /// The pick, or nil when cancelled. Called once; the controller has already dismissed itself.
    var onFinish: ((SRGBColor?) -> Void)?
    /// The cursor moved onto a screen, for capturing displays lazily.
    var onScreen: ((LoupeScreen) -> Void)?

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var monitor: Any?
    private var cursorHidden = false
    /// Frontmost app before the loupe took focus; gets it back on dismiss so ⌘V lands there.
    private var previousApp: NSRunningApplication?

    init(model: LoupeModel) {
        self.model = model
    }

    var isPresented: Bool { !windows.isEmpty }

    func present() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            guard let loupeScreen = model.screens.first(where: { $0.id == screen.displayID }) else { continue }
            let window = OverlayWindow(screen: screen, interactive: true)
            window.contentView = NSHostingView(rootView: LoupeScreenView(model: model, screen: loupeScreen))
            windows[loupeScreen.id] = window
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost == NSRunningApplication.current ? nil : frontmost
        NSApp.activate()
        if let screen = model.move(to: NSEvent.mouseLocation) { onScreen?(screen) }
        for (id, window) in windows {
            if id == model.screenID {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFront(nil)
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            return handle(event) ? nil : event
        }
        NSCursor.hide()
        cursorHidden = true
    }

    func dismiss() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if cursorHidden { NSCursor.unhide() }
        cursorHidden = false
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate(from: .current, options: [])
        }
        previousApp = nil
    }

    func pick() {
        finish(model.centerColor)
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ color: SRGBColor?) {
        guard isPresented else { return }
        dismiss()
        onFinish?(color)
    }

    /// Follows a global point: the mouse, or a demo.
    func follow(_ point: CGPoint) {
        let before = model.screenID
        guard let screen = model.move(to: point) else { return }
        if screen.id != before {
            windows[screen.id]?.makeKey()
            onScreen?(screen)
        }
    }

    /// True when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .mouseMoved, .leftMouseDragged:
            follow(NSEvent.mouseLocation)
            return false
        case .leftMouseDown:
            pick()
            return true
        case .rightMouseDown:
            cancel()
            return true
        case .keyDown:
            log.debug("loupe key \(event.keyCode)")
            let step = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 53: cancel() // Escape
            case 36, 76: pick() // Return, keypad Enter
            case 123: nudge(dx: -step, dy: 0)
            case 124: nudge(dx: step, dy: 0)
            case 125: nudge(dx: 0, dy: step)
            case 126: nudge(dx: 0, dy: -step)
            default: return false
            }
            return true
        default:
            return false
        }
    }

    private func nudge(dx: Int, dy: Int) {
        guard let point = model.nudge(dx: dx, dy: dy) else { return }
        // Moves the real (hidden) cursor too, so the next mouse move carries on from the nudged pixel.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primaryHeight - point.y))
    }

    /// Renders the loupe's screen. Design review only.
    func debugSnapshot() -> NSImage? {
        guard let id = model.screenID, let view = windows[id]?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func debugWindowCount() -> Int { windows.count }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
