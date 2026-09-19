import AppKit
import SwiftUI

/// The tile's mouse, handled in AppKit: clicks arrive with their count and modifiers the moment the button goes
/// up, and a drag starts a real dragging session, which can carry several files (SwiftUI's `onDrag` carries one).
/// Dragging out is always a copy: the files stay where they are.
struct TileMouse: NSViewRepresentable {
    /// Mouse up without a drag.
    let click: @MainActor (_ count: Int, _ flags: NSEvent.ModifierFlags) -> Void
    /// A drag is starting on this tile: what it carries, and a picture for each item.
    let drag: @MainActor () -> [(writer: any NSPasteboardWriting, image: NSImage?)]

    func makeNSView(context: Context) -> TileMouseView {
        let view = TileMouseView()
        view.click = click
        view.drag = drag
        return view
    }

    func updateNSView(_ view: TileMouseView, context: Context) {
        view.click = click
        view.drag = drag
    }
}

final class TileMouseView: NSView, NSDraggingSource {
    var click: (@MainActor (Int, NSEvent.ModifierFlags) -> Void)?
    var drag: (@MainActor () -> [(writer: any NSPasteboardWriting, image: NSImage?)])?

    private var down: NSEvent?
    private var dragging = false

    /// Points the pointer travels before a press becomes a drag.
    private static let slop: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        down = event
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down, !dragging else { return }
        let from = down.locationInWindow
        let to = event.locationInWindow
        guard hypot(to.x - from.x, to.y - from.y) >= Self.slop else { return }
        dragging = true
        let payloads = drag?() ?? []
        guard !payloads.isEmpty else { return }
        let items = payloads.enumerated().map { index, payload in
            let item = NSDraggingItem(pasteboardWriter: payload.writer)
            // A small fan of pictures under the pointer.
            let size = CGSize(width: 72, height: 48)
            let offset = CGFloat(min(index, 4)) * 4
            let origin = convert(from, from: nil)
            let frame = CGRect(x: origin.x - size.width / 2 + offset, y: origin.y - size.height / 2 - offset, width: size.width, height: size.height)
            item.setDraggingFrame(frame, contents: payload.image ?? Self.placeholder)
            return item
        }
        beginDraggingSession(with: items, event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { down = nil }
        guard down != nil, !dragging else { return }
        click?(event.clickCount, event.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        down = nil
    }

    private static let placeholder: NSImage = {
        let image = NSImage(size: CGSize(width: 72, height: 48))
        image.lockFocus()
        NSColor(white: 0.2, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 72, height: 48), xRadius: 7, yRadius: 7).fill()
        image.unlockFocus()
        return image
    }()
}
