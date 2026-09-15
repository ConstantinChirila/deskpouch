import AppKit

/// Idle glyph candidates drawn for 18 pt after the brand mark: a soft drawstring pouch, open at the top, strings
/// out to the sides, three meter bars rising from the opening. Template images.
@MainActor
public enum MenubarGlyph: String, CaseIterable, Sendable {
    /// Solid body, strings as short strokes with a bead, bars above.
    case pouch
    /// 2 pt outline body, same strings and bars: the pack's glyph, heavier.
    case pouchOutline

    public func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func draw() {
        let body = pouchBody()
        switch self {
        case .pouch:
            body.fill()
        case .pouchOutline:
            body.lineWidth = 1.8
            body.lineJoinStyle = .round
            body.stroke()
        }
        strings().stroke()
        beads().fill()
        bars(bottom: 5.5, heights: [3, 5, 3]).fill()
    }

    /// Body: wide open lip with a soft dip, sides flaring to a round bottom. Lip at y 7, bottom at 16.5.
    private func pouchBody() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 4.5, y: 7))
        p.curve(to: NSPoint(x: 13.5, y: 7), controlPoint1: NSPoint(x: 7, y: 8.2), controlPoint2: NSPoint(x: 11, y: 8.2))
        p.curve(to: NSPoint(x: 15.5, y: 13), controlPoint1: NSPoint(x: 14.5, y: 8.5), controlPoint2: NSPoint(x: 15.5, y: 10.5))
        p.curve(to: NSPoint(x: 9, y: 16.5), controlPoint1: NSPoint(x: 15.5, y: 15.5), controlPoint2: NSPoint(x: 12.5, y: 16.5))
        p.curve(to: NSPoint(x: 2.5, y: 13), controlPoint1: NSPoint(x: 5.5, y: 16.5), controlPoint2: NSPoint(x: 2.5, y: 15.5))
        p.curve(to: NSPoint(x: 4.5, y: 7), controlPoint1: NSPoint(x: 2.5, y: 10.5), controlPoint2: NSPoint(x: 3.5, y: 8.5))
        p.close()
        return p
    }

    /// Drawstrings: from the lip corners out and down.
    private func strings() -> NSBezierPath {
        let p = NSBezierPath()
        p.lineWidth = 1.6
        p.lineCapStyle = .round
        p.move(to: NSPoint(x: 4.5, y: 7.5))
        p.curve(to: NSPoint(x: 1.8, y: 10.2), controlPoint1: NSPoint(x: 3.2, y: 7.8), controlPoint2: NSPoint(x: 2.2, y: 8.8))
        p.move(to: NSPoint(x: 13.5, y: 7.5))
        p.curve(to: NSPoint(x: 16.2, y: 10.2), controlPoint1: NSPoint(x: 14.8, y: 7.8), controlPoint2: NSPoint(x: 15.8, y: 8.8))
        return p
    }

    private func beads() -> NSBezierPath {
        let p = NSBezierPath()
        p.append(NSBezierPath(ovalIn: NSRect(x: 0.5, y: 9.5, width: 2.6, height: 2.6)))
        p.append(NSBezierPath(ovalIn: NSRect(x: 14.9, y: 9.5, width: 2.6, height: 2.6)))
        return p
    }

    /// Three rounded bars centred on x = 9 with their bottoms at `bottom`, 2 wide with 1.5 gaps.
    private func bars(bottom: CGFloat, heights: [CGFloat]) -> NSBezierPath {
        let p = NSBezierPath()
        let width: CGFloat = 1.8
        let gap: CGFloat = 1.7
        let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
        var x = 9 - total / 2
        for h in heights {
            p.append(NSBezierPath(roundedRect: NSRect(x: x, y: bottom - h, width: width, height: h), xRadius: 1, yRadius: 1))
            x += width + gap
        }
        return p
    }
}
