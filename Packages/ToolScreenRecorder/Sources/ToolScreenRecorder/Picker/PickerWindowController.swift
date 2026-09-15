import AppKit
import DeskpouchCore
import SwiftUI

/// One borderless window per screen, above everything, showing `PickerScreenView`. Escape cancels, Return records.
@MainActor
final class PickerWindowController {
    let model: PickerModel
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var cursorPushed = false

    init(model: PickerModel) {
        self.model = model
    }

    var isPresented: Bool { !windows.isEmpty }

    func present() {
        guard windows.isEmpty else { return }
        for screen in model.screens {
            let window = PickerPanelWindow(contentRect: screen.frame)
            window.contentView = NSHostingView(rootView: PickerScreenView(model: model, screen: screen))
            windows.append(window)
        }
        NSApp.activate()
        for (index, window) in windows.enumerated() {
            if model.screens[index].id == model.toolbarScreenID {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFront(nil)
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Escape
                model.cancel()
                return nil
            case 36, 76: // Return, keypad Enter
                model.confirm()
                return nil
            default:
                return event
            }
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.model.snapToAspect = event.modifierFlags.contains(.shift)
            return event
        }
        NSCursor.crosshair.push()
        cursorPushed = true
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        keyMonitor = nil
        flagsMonitor = nil
        if cursorPushed { NSCursor.pop() }
        cursorPushed = false
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    /// Renders the toolbar screen's picker content. Design review only.
    func debugSnapshot() -> NSImage? {
        guard let index = model.screens.firstIndex(where: { $0.id == model.toolbarScreenID }),
              index < windows.count, let view = windows[index].contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

@MainActor
private final class PickerPanelWindow: NSWindow {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
