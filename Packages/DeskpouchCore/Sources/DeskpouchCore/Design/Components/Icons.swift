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
