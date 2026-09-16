import CoreGraphics
import Foundation

/// Pure geometry for the picker and the capture configuration. No AppKit, so it is unit tested.
public enum CaptureGeometry {
    /// Output pixels per screen point for a display. Regions and windows on the display share it, so a region
    /// capture is as crisp as a full-screen one. `maxHeight` fits the full display into that many pixel rows;
    /// nil keeps native pixels.
    public static func pixelsPerPoint(displayPoints: CGSize, backingScale: CGFloat, maxHeight: CGFloat?) -> CGFloat {
        let nativeHeight = displayPoints.height * backingScale
        guard let maxHeight, nativeHeight > maxHeight else { return backingScale }
        return backingScale * maxHeight / nativeHeight
    }

    /// Encoder-friendly output size: whole even numbers, never below 2.
    public static func outputSize(points: CGSize, pixelsPerPoint: CGFloat) -> CGSize {
        func even(_ value: CGFloat) -> CGFloat {
            let rounded = Int((value * pixelsPerPoint).rounded())
            return CGFloat(max(2, rounded - rounded % 2))
        }
        return CGSize(width: even(points.width), height: even(points.height))
    }

    /// Rectangle spanned by a drag. With `aspect` (width / height) the far corner is pulled in so the rect keeps
    /// that ratio and never reaches past the pointer.
    public static func rect(from anchor: CGPoint, to point: CGPoint, aspect: CGFloat? = nil) -> CGRect {
        var width = point.x - anchor.x
        var height = point.y - anchor.y
        if let aspect, aspect > 0 {
            let w = min(abs(width), abs(height) * aspect)
            width = w * (width < 0 ? -1 : 1)
            height = (w / aspect) * (height < 0 ? -1 : 1)
        }
        return CGRect(x: min(anchor.x, anchor.x + width), y: min(anchor.y, anchor.y + height),
                      width: abs(width), height: abs(height))
    }

    /// Moves `rect` so it stays inside `bounds`; shrinks it when it is larger than the bounds.
    public static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }

    /// Whole-point rectangle, so the capture and the chrome agree on pixel edges.
    public static func integral(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// "1040 × 760".
    public static func dimensionLabel(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }
}
