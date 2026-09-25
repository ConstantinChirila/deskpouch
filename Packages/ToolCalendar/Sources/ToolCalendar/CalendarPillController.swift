import AppKit
import DeskpouchCore
import SwiftUI

/// The calendar pills' own window (plan 11): separate from the shared overlay so it can sit somewhere else,
/// stack up to three pills and be dragged. Anchored by the stack's top-right corner, stored per display as an
/// offset from the screen's visible top-right; default 16 pt in from the right, 10 pt under the menubar.
@MainActor
final class CalendarPillController: PillPresenter {
    private let model: CalendarModel
    private var panel: NSPanel?
    private var hosting: NSHostingView<CalendarPillStackView>?
    /// Where the stack's top-right corner sits while shown, in global AppKit coordinates.
    private var anchor: CGPoint?
    private var dragStart: (mouse: CGPoint, anchor: CGPoint)?
    private let defaults: UserDefaults

    /// Room around the pills for the ring and the shadow.
    static let margin: CGFloat = 26
    static let defaultOffset = CGSize(width: 16, height: 10)
    static let offsetKey = "calendar.pillOffset"

    init(model: CalendarModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
    }

    var windowNumber: Int? {
        panel?.isVisible == true ? panel?.windowNumber : nil
    }

    /// For the demo's log.
    var frame: CGRect? { panel?.frame }

    /// Shows, resizes or hides the window to match the model. Call after every change to the pills or the
    /// message.
    func refresh() {
        let empty = model.pills.pills.isEmpty && model.message == nil
        if empty {
            panel?.orderOut(nil)
            anchor = nil
            return
        }
        let panel = self.panel ?? makePanel()
        if anchor == nil { anchor = storedAnchor(on: NSScreen.main ?? NSScreen.screens.first) }
        // SwiftUI applies the model change on its next pass; size the window after it.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            layout()
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = PillPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        let view = CalendarPillStackView(model: model, actions: PillActions(
            dragChanged: { [weak self] in self?.dragChanged() },
            dragEnded: { [weak self] in self?.dragEnded() },
            reset: { [weak self] in self?.resetPosition() }
        ))
        let hosting = NSHostingView(rootView: view)
        // The window follows the stack's size (`layout`); the view only reports it.
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    private func layout() {
        guard let panel, let hosting, let anchor else { return }
        let size = hosting.fittingSize
        let m = Self.margin
        let frame = CGRect(x: anchor.x + m - size.width, y: anchor.y + m - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        hosting.frame = CGRect(origin: .zero, size: size)
    }

    // MARK: Position

    private func storedAnchor(on screen: NSScreen?) -> CGPoint {
        guard let screen else { return .zero }
        let visible = screen.visibleFrame
        var offset = Self.defaultOffset
        if let pair = (defaults.dictionary(forKey: Self.offsetKey) as? [String: [Double]])?[screen.pillKey], pair.count == 2 {
            offset = CGSize(width: pair[0], height: pair[1])
        }
        let point = CGPoint(x: visible.maxX - offset.width, y: visible.maxY - offset.height)
        return clamp(point, to: visible)
    }

    /// Keeps at least a pill's worth on screen after a resolution change.
    private func clamp(_ point: CGPoint, to visible: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, visible.minX + 200), visible.maxX), y: min(max(point.y, visible.minY + 60), visible.maxY))
    }

    private func dragChanged() {
        guard let anchor else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, anchor) }
        guard let start = dragStart else { return }
        self.anchor = CGPoint(x: start.anchor.x + mouse.x - start.mouse.x, y: start.anchor.y + mouse.y - start.mouse.y)
        layout()
    }

    private func dragEnded() {
        dragStart = nil
        guard let anchor else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let clamped = clamp(anchor, to: visible)
        self.anchor = clamped
        layout()
        var stored = (defaults.dictionary(forKey: Self.offsetKey) as? [String: [Double]]) ?? [:]
        stored[screen.pillKey] = [Double(visible.maxX - clamped.x), Double(visible.maxY - clamped.y)]
        defaults.set(stored, forKey: Self.offsetKey)
    }

    private func resetPosition() {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor ?? .zero) } ?? NSScreen.main
        guard let screen else { return }
        var stored = (defaults.dictionary(forKey: Self.offsetKey) as? [String: [Double]]) ?? [:]
        stored[screen.pillKey] = nil
        defaults.set(stored, forKey: Self.offsetKey)
        anchor = storedAnchor(on: screen)
        layout()
    }
}

/// Clicks on a pill must work without taking focus from the app in front.
private final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private extension NSScreen {
    /// The display's id as a defaults key.
    var pillKey: String {
        let id = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return String(id)
    }
}

struct PillActions {
    var dragChanged: @MainActor () -> Void
    var dragEnded: @MainActor () -> Void
    var reset: @MainActor () -> Void
}
