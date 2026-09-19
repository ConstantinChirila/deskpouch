import SwiftUI

/// Stroke icons traced from the design mocks. All are drawn in a 16 unit box and scaled to `rect`.
/// Use with `.stroke(style:)`; they carry no fill.

public struct MicIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        // Capsule body: rect x5.5 y1.5 w5 h8 rx2.5
        p.addRoundedRect(in: CGRect(x: 5.5, y: 1.5, width: 5, height: 8), cornerSize: CGSize(width: 2.5, height: 2.5))
        // Cradle: M3 7.5 a5 5 0 0 0 10 0 (lower half circle, centre 8,7.5)
        p.move(to: CGPoint(x: 3, y: 7.5))
        p.addArc(center: CGPoint(x: 8, y: 7.5), radius: 5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        // Stem: M8 12.5 v2
        p.move(to: CGPoint(x: 8, y: 12.5))
        p.addLine(to: CGPoint(x: 8, y: 14.5))
        return p.scaled(toFit: rect)
    }
}

public struct PouchIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        // Bag: M3.5 6.5 h9 l1 7.5 h-11 z
        p.move(to: CGPoint(x: 3.5, y: 6.5))
        p.addLine(to: CGPoint(x: 12.5, y: 6.5))
        p.addLine(to: CGPoint(x: 13.5, y: 14))
        p.addLine(to: CGPoint(x: 2.5, y: 14))
        p.closeSubpath()
        // Handle: M5.5 6.5 V5 a2.5 2.5 0 0 1 5 0 v1.5 (upper half circle, centre 8,5)
        p.move(to: CGPoint(x: 5.5, y: 6.5))
        p.addLine(to: CGPoint(x: 5.5, y: 5))
        p.addArc(center: CGPoint(x: 8, y: 5), radius: 2.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: 10.5, y: 6.5))
        return p.scaled(toFit: rect)
    }
}

/// Check mark: M3 8.5 l3 3 7-7.
public struct CheckIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 8.5))
        p.addLine(to: CGPoint(x: 6, y: 11.5))
        p.addLine(to: CGPoint(x: 13, y: 4.5))
        return p.scaled(toFit: rect)
    }
}

public struct GearIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 5.5, y: 5.5, width: 5, height: 5))
        let ticks: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 8, y: 1.5), CGPoint(x: 8, y: 3.5)),
            (CGPoint(x: 8, y: 12.5), CGPoint(x: 8, y: 14.5)),
            (CGPoint(x: 1.5, y: 8), CGPoint(x: 3.5, y: 8)),
            (CGPoint(x: 12.5, y: 8), CGPoint(x: 14.5, y: 8)),
            (CGPoint(x: 3.4, y: 3.4), CGPoint(x: 4.8, y: 4.8)),
            (CGPoint(x: 11.2, y: 11.2), CGPoint(x: 12.6, y: 12.6)),
            (CGPoint(x: 3.4, y: 12.6), CGPoint(x: 4.8, y: 11.2)),
            (CGPoint(x: 11.2, y: 4.8), CGPoint(x: 12.6, y: 3.4)),
        ]
        for (a, b) in ticks {
            p.move(to: a)
            p.addLine(to: b)
        }
        return p.scaled(toFit: rect)
    }
}

/// Two overlapping sheets: rect x5.5 y5.5 w8 h8 rx1.5 plus the back sheet outline.
public struct CopyIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 5.5, y: 5.5, width: 8, height: 8), cornerSize: CGSize(width: 1.5, height: 1.5))
        // M10.5 5.5 v-2 a1 1 0 0 0 -1 -1 h-6 a1 1 0 0 0 -1 1 v6 a1 1 0 0 0 1 1 h2
        p.move(to: CGPoint(x: 10.5, y: 5.5))
        p.addLine(to: CGPoint(x: 10.5, y: 3.5))
        p.addArc(center: CGPoint(x: 9.5, y: 3.5), radius: 1, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        p.addLine(to: CGPoint(x: 3.5, y: 2.5))
        p.addArc(center: CGPoint(x: 3.5, y: 3.5), radius: 1, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: 2.5, y: 9.5))
        p.addArc(center: CGPoint(x: 3.5, y: 9.5), radius: 1, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: 5.5, y: 10.5))
        return p.scaled(toFit: rect)
    }
}

/// Down chevron: M4 6.5 l4 4 4-4. Rotate for other directions.
public struct ChevronIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 6.5))
        p.addLine(to: CGPoint(x: 8, y: 10.5))
        p.addLine(to: CGPoint(x: 12, y: 6.5))
        return p.scaled(toFit: rect)
    }
}

/// Display on a stand: rect x1.5 y2.5 w13 h9 rx1.5, foot M5.5 14h5, neck M8 11.5V14.
public struct ScreenIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 1.5, y: 2.5, width: 13, height: 9), cornerSize: CGSize(width: 1.5, height: 1.5))
        p.move(to: CGPoint(x: 5.5, y: 14))
        p.addLine(to: CGPoint(x: 10.5, y: 14))
        p.move(to: CGPoint(x: 8, y: 11.5))
        p.addLine(to: CGPoint(x: 8, y: 14))
        return p.scaled(toFit: rect)
    }
}

/// Window with a title bar: rect x1.5 y2.5 w13 h11 rx1.5, bar M1.5 5.5h13.
public struct WindowIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 1.5, y: 2.5, width: 13, height: 11), cornerSize: CGSize(width: 1.5, height: 1.5))
        p.move(to: CGPoint(x: 1.5, y: 5.5))
        p.addLine(to: CGPoint(x: 14.5, y: 5.5))
        return p.scaled(toFit: rect)
    }
}

/// Four corner brackets, the region picker's mark.
public struct RegionIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        // M2 5V3a1 1 0 0 1 1-1h2
        p.move(to: CGPoint(x: 2, y: 5)); p.addLine(to: CGPoint(x: 2, y: 3))
        p.addArc(center: CGPoint(x: 3, y: 3), radius: 1, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: 5, y: 2))
        // M11 2h2a1 1 0 0 1 1 1v2
        p.move(to: CGPoint(x: 11, y: 2)); p.addLine(to: CGPoint(x: 13, y: 2))
        p.addArc(center: CGPoint(x: 13, y: 3), radius: 1, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: 14, y: 5))
        // M14 11v2a1 1 0 0 1-1 1h-2
        p.move(to: CGPoint(x: 14, y: 11)); p.addLine(to: CGPoint(x: 14, y: 13))
        p.addArc(center: CGPoint(x: 13, y: 13), radius: 1, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: 11, y: 14))
        // M5 14H3a1 1 0 0 1-1-1v-2
        p.move(to: CGPoint(x: 5, y: 14)); p.addLine(to: CGPoint(x: 3, y: 14))
        p.addArc(center: CGPoint(x: 3, y: 13), radius: 1, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 2, y: 11))
        return p.scaled(toFit: rect)
    }
}

/// Speaker with one wave: M2 6v4h3l4 3V3L5 6z, M11.5 5.5a3.5 3.5 0 0 1 0 5.
public struct SpeakerIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 2, y: 6))
        p.addLine(to: CGPoint(x: 2, y: 10))
        p.addLine(to: CGPoint(x: 5, y: 10))
        p.addLine(to: CGPoint(x: 9, y: 13))
        p.addLine(to: CGPoint(x: 9, y: 3))
        p.addLine(to: CGPoint(x: 5, y: 6))
        p.closeSubpath()
        p.move(to: CGPoint(x: 11.5, y: 5.5))
        p.addArc(center: CGPoint(x: 11.5, y: 8), radius: 2.5, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        return p.scaled(toFit: rect)
    }
}

/// Magnifier: circle at (7,7) r4.5, handle to (14,14).
public struct SearchIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 9, height: 9))
        p.move(to: CGPoint(x: 10.5, y: 10.5))
        p.addLine(to: CGPoint(x: 14, y: 14))
        return p.scaled(toFit: rect)
    }
}

/// Bin: lid line, handle, tapered body.
public struct TrashIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 2.5, y: 4.5)); p.addLine(to: CGPoint(x: 13.5, y: 4.5))
        p.move(to: CGPoint(x: 6, y: 4.5)); p.addLine(to: CGPoint(x: 6, y: 3))
        p.addArc(center: CGPoint(x: 7, y: 3), radius: 1, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: 9, y: 2))
        p.addArc(center: CGPoint(x: 9, y: 3), radius: 1, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: 10, y: 4.5))
        p.move(to: CGPoint(x: 4, y: 4.5)); p.addLine(to: CGPoint(x: 4.7, y: 13))
        p.addArc(center: CGPoint(x: 5.7, y: 13), radius: 1, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: 10.3, y: 14))
        p.addArc(center: CGPoint(x: 10.3, y: 13), radius: 1, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: 12, y: 4.5))
        return p.scaled(toFit: rect)
    }
}

/// Folder: M1.5 4.5a1 1 0 0 1 1-1h3l1.5 1.5h6.5a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1z
public struct FolderIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 1.5, y: 4.5))
        p.addArc(center: CGPoint(x: 2.5, y: 4.5), radius: 1, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: 5.5, y: 3.5))
        p.addLine(to: CGPoint(x: 7, y: 5))
        p.addLine(to: CGPoint(x: 13.5, y: 5))
        p.addArc(center: CGPoint(x: 13.5, y: 6), radius: 1, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: 14.5, y: 12))
        p.addArc(center: CGPoint(x: 13.5, y: 12), radius: 1, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: 2.5, y: 13))
        p.addArc(center: CGPoint(x: 2.5, y: 12), radius: 1, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p.scaled(toFit: rect)
    }
}

/// Pencil: body on the diagonal, tip bottom-left.
public struct PencilIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 10.5, y: 3)); p.addLine(to: CGPoint(x: 13, y: 5.5))
        p.addLine(to: CGPoint(x: 5.5, y: 13)); p.addLine(to: CGPoint(x: 2.5, y: 13.5))
        p.addLine(to: CGPoint(x: 3, y: 10.5)); p.closeSubpath()
        p.move(to: CGPoint(x: 9, y: 4.5)); p.addLine(to: CGPoint(x: 11.5, y: 7))
        return p.scaled(toFit: rect)
    }
}

/// Trim: in and out brackets around a strip.
public struct TrimIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 5.5, y: 3)); p.addLine(to: CGPoint(x: 3, y: 3))
        p.addLine(to: CGPoint(x: 3, y: 13)); p.addLine(to: CGPoint(x: 5.5, y: 13))
        p.move(to: CGPoint(x: 10.5, y: 3)); p.addLine(to: CGPoint(x: 13, y: 3))
        p.addLine(to: CGPoint(x: 13, y: 13)); p.addLine(to: CGPoint(x: 10.5, y: 13))
        p.move(to: CGPoint(x: 6.5, y: 8)); p.addLine(to: CGPoint(x: 9.5, y: 8))
        return p.scaled(toFit: rect)
    }
}

/// Arrow pointing up-right.
public struct ArrowIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 13)); p.addLine(to: CGPoint(x: 13, y: 3))
        p.move(to: CGPoint(x: 6.5, y: 3)); p.addLine(to: CGPoint(x: 13, y: 3)); p.addLine(to: CGPoint(x: 13, y: 9.5))
        return p.scaled(toFit: rect)
    }
}

/// Rounded rectangle outline.
public struct BoxIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 2.5, y: 3.5, width: 11, height: 9), cornerSize: CGSize(width: 1.5, height: 1.5))
        return p.scaled(toFit: rect)
    }
}

/// Capital T.
public struct TextIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 4.5)); p.addLine(to: CGPoint(x: 3, y: 3)); p.addLine(to: CGPoint(x: 13, y: 3))
        p.addLine(to: CGPoint(x: 13, y: 4.5))
        p.move(to: CGPoint(x: 8, y: 3)); p.addLine(to: CGPoint(x: 8, y: 13))
        p.move(to: CGPoint(x: 6, y: 13)); p.addLine(to: CGPoint(x: 10, y: 13))
        return p.scaled(toFit: rect)
    }
}

/// Pixel grid: a square split into four cells.
public struct BlurIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11), cornerSize: CGSize(width: 1.5, height: 1.5))
        p.move(to: CGPoint(x: 8, y: 2.5)); p.addLine(to: CGPoint(x: 8, y: 13.5))
        p.move(to: CGPoint(x: 2.5, y: 8)); p.addLine(to: CGPoint(x: 13.5, y: 8))
        return p.scaled(toFit: rect)
    }
}

/// Circle; the number is drawn as text on top.
public struct BadgeIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 2, y: 2, width: 12, height: 12))
        return p.scaled(toFit: rect)
    }
}

/// Counter-clockwise hook. `RedoIcon` is its mirror.
public struct UndoIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 5.5, y: 3)); p.addLine(to: CGPoint(x: 2.5, y: 6)); p.addLine(to: CGPoint(x: 5.5, y: 9))
        p.move(to: CGPoint(x: 2.5, y: 6)); p.addLine(to: CGPoint(x: 9.5, y: 6))
        p.addArc(center: CGPoint(x: 9.5, y: 9.5), radius: 3.5, startAngle: .degrees(270), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: 6, y: 13))
        return p.scaled(toFit: rect)
    }
}

public struct RedoIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        UndoIcon().path(in: rect)
            .applying(CGAffineTransform(translationX: rect.midX, y: 0).scaledBy(x: -1, y: 1).translatedBy(x: -rect.midX, y: 0))
    }
}

/// X.
public struct CloseIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 4)); p.addLine(to: CGPoint(x: 12, y: 12))
        p.move(to: CGPoint(x: 12, y: 4)); p.addLine(to: CGPoint(x: 4, y: 12))
        return p.scaled(toFit: rect)
    }
}

extension Path {
    /// Scales a path authored in a 16 unit box into `rect`, preserving aspect.
    fileprivate func scaled(toFit rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let offset = CGPoint(
            x: rect.minX + (rect.width - 16 * scale) / 2,
            y: rect.minY + (rect.height - 16 * scale) / 2
        )
        let t = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
        return applying(t)
    }
}

extension StrokeStyle {
    /// Round caps and joins, the stroke style every mock icon uses.
    public static func icon(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

/// Eyedropper, tip at the bottom left.
public struct DropperIcon: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        // Bulb: a short capsule across the top right corner.
        p.move(to: CGPoint(x: 9, y: 4.5)); p.addLine(to: CGPoint(x: 10.8, y: 2.7))
        p.addArc(center: CGPoint(x: 12.05, y: 3.95), radius: 1.77, startAngle: .degrees(225), endAngle: .degrees(45), clockwise: false)
        p.addLine(to: CGPoint(x: 11.5, y: 7))
        // Collar.
        p.move(to: CGPoint(x: 8, y: 3.5)); p.addLine(to: CGPoint(x: 12.5, y: 8))
        // Barrel down to the tip.
        p.move(to: CGPoint(x: 9.5, y: 5.5)); p.addLine(to: CGPoint(x: 3.5, y: 11.5))
        p.addLine(to: CGPoint(x: 3, y: 13)); p.addLine(to: CGPoint(x: 4.5, y: 12.5))
        p.addLine(to: CGPoint(x: 10.5, y: 6.5))
        return p.scaled(toFit: rect)
    }
}
