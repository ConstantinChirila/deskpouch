import CoreGraphics
import Foundation

/// Output resolution for a still capture. `native` keeps the display's full backing-store pixels (2x on Retina,
/// 1x on a non-Retina external display); `x1` downsamples to one pixel per point via `ImageWriter.downscale`.
public enum CaptureScale: String, CaseIterable, Sendable {
    case native
    case x1

    /// "2x" / "1x" for the Scale option row. `nativeScale` is the main screen's backing scale factor, so
    /// `.native` reads correctly on a non-Retina display instead of a hard-coded "2x".
    public func label(nativeScale: CGFloat) -> String {
        switch self {
        case .native: "\(Int(nativeScale.rounded()))x"
        case .x1: "1x"
        }
    }
}
