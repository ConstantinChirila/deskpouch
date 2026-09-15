import CoreGraphics
import Foundation

/// Pure geometry for the picker and the capture configuration. No AppKit, so it is unit tested.
enum CaptureGeometry {
    /// The "High" preset fits a full-screen recording into this many pixel rows.
    static let highQualityMaxHeight: CGFloat = 1080

    /// Output pixels per screen point for a display. Regions and windows on the display share it, so a region
    /// recording is as crisp as a full-screen one.
    static func pixelsPerPoint(displayPoints: CGSize, backingScale: CGFloat, quality: RecorderSettings.Quality) -> CGFloat {
        switch quality {
        case .full:
            return backingScale
        case .high:
            let nativeHeight = displayPoints.height * backingScale
            guard nativeHeight > highQualityMaxHeight else { return backingScale }
            return backingScale * highQualityMaxHeight / nativeHeight
        }
    }

    /// Encoder-friendly output size: whole even numbers, never below 2.
    static func outputSize(points: CGSize, pixelsPerPoint: CGFloat) -> CGSize {
        func even(_ value: CGFloat) -> CGFloat {
            let rounded = Int((value * pixelsPerPoint).rounded())
            return CGFloat(max(2, rounded - rounded % 2))
        }
        return CGSize(width: even(points.width), height: even(points.height))
    }

    /// Rectangle spanned by a drag. With `aspect` (width / height) the far corner is pulled in so the rect keeps
    /// that ratio and never reaches past the pointer.
    static func rect(from anchor: CGPoint, to point: CGPoint, aspect: CGFloat? = nil) -> CGRect {
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
    static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }

    /// Whole-point rectangle, so the capture and the chrome agree on pixel edges.
    static func integral(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// "1040 × 760".
    static func dimensionLabel(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    /// "1040 × 760 · 60 fps" for the recording pill.
    static func detail(points: CGSize, frameRate: Int) -> String {
        "\(dimensionLabel(points)) · \(frameRate) fps"
    }
}
