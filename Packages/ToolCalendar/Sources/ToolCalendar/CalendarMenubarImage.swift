import AppKit
import DeskpouchCore

/// The calendar's status item image (mock "Menubar item A · Glyph and text"): a calendar glyph and the text. Plain
/// template text more than 5 minutes out, an amber capsule in the last 5 minutes, a mint capsule while the event
/// runs.
@MainActor
public enum CalendarMenubarImage {
    public static func make(_ menubar: Agenda.Menubar) -> NSImage {
        switch menubar.tint {
        case .plain: plain(menubar.text)
        case .soon: capsule(menubar.text, fill: Theme.NSColors.accent)
        case .live: capsule(menubar.text, fill: Theme.NSColors.ok)
        }
    }

    private static let glyph: CGFloat = 13
    private static let gap: CGFloat = 5

    private static func plain(_ text: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let label = text as NSString
        let textSize = label.size(withAttributes: attributes)
        let size = NSSize(width: ceil(glyph + gap + textSize.width + 1), height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            drawGlyph(in: NSRect(x: 0, y: (rect.height - glyph) / 2, width: glyph, height: glyph), color: .black)
            label.draw(at: NSPoint(x: glyph + gap, y: (rect.height - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func capsule(_ text: String, fill: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        let ink = Theme.NSColors.accentInk
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let label = text as NSString
        let textSize = label.size(withAttributes: attributes)
        let size = NSSize(width: ceil(7 + glyph + gap + textSize.width + 9), height: 20)
        let image = NSImage(size: size, flipped: true) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            drawGlyph(in: NSRect(x: 7, y: (rect.height - glyph) / 2, width: glyph, height: glyph), color: ink)
            label.draw(at: NSPoint(x: 7 + glyph + gap, y: (rect.height - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// `CalendarIcon` redrawn with AppKit: page, header rule, two rings. 16 unit box, flipped.
    private static func drawGlyph(in rect: NSRect, color: NSColor) {
        let s = rect.width / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        let path = NSBezierPath(roundedRect: NSRect(origin: p(2, 3), size: NSSize(width: 12 * s, height: 11 * s)), xRadius: 2.5 * s, yRadius: 2.5 * s)
        path.move(to: p(2, 7)); path.line(to: p(14, 7))
        path.move(to: p(5.5, 1.5)); path.line(to: p(5.5, 4.5))
        path.move(to: p(10.5, 1.5)); path.line(to: p(10.5, 4.5))
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}
