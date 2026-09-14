import AppKit

/// Status item images. Idle is a template glyph; listening and recording are drawn in colour.
@MainActor
public enum MenubarIcon {
    /// Pouch glyph, 18x18, template so it follows the menubar appearance.
    public static func idle() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            let path = NSBezierPath()
            let s: CGFloat = 1 // 16 unit art in an 18 box, 1pt margin
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x + s, y: y + s) }
            // Bag
            path.move(to: pt(3.5, 6.5))
            path.line(to: pt(12.5, 6.5))
            path.line(to: pt(13.5, 14))
            path.line(to: pt(2.5, 14))
            path.close()
            // Handle: upper half circle centred (8,5) r2.5
            path.move(to: pt(5.5, 6.5))
            path.line(to: pt(5.5, 5))
            path.appendArc(withCenter: pt(8, 5), radius: 2.5, startAngle: 180, endAngle: 360, clockwise: false)
            path.line(to: pt(10.5, 6.5))
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Amber pill with a 7 bar meter, 40x20.
    public static func listening(levels: [Float]) -> NSImage {
        let size = NSSize(width: 40, height: 20)
        let image = NSImage(size: size, flipped: true) { rect in
            let pill = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            Theme.NSColors.accent.withAlphaComponent(0.18).setFill()
            pill.fill()

            let barWidth: CGFloat = 2
            let gap: CGFloat = 2
            let minH: CGFloat = 4
            let maxH: CGFloat = 13
            let bars = Array(levels.suffix(7))
            let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(max(bars.count - 1, 0)) * gap
            var x = (rect.width - totalWidth) / 2
            Theme.NSColors.accentHigh.setFill()
            for level in bars {
                let l = CGFloat(min(max(level, 0), 1))
                let h = minH + (maxH - minH) * l
                let bar = NSBezierPath(
                    roundedRect: NSRect(x: x, y: (rect.height - h) / 2, width: barWidth, height: h),
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                )
                bar.fill()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
