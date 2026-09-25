import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct StillCaptureError: LocalizedError {
    let message: String
    public var errorDescription: String? { message }
}

/// A quick, non-streaming screenshot of a picker's selection, over `SCScreenshotManager.captureImage`. Used by
/// the screenshot and text-grab tools instead of the recorder's `SCStream`.
///
/// Loads its own `SCShareableContent`, so a caller only needs the `PickerSelection`; the picker windows must
/// already be dismissed before this runs; and region and screen captures exclude Deskpouch's own app the same
/// way the recorder does (`ShareableContentLoader.ownApplication`), so the pill, panel and picker never appear
/// in the file.
@MainActor
public enum StillCapture {
    /// A capture and the pixels per point it was taken at (1 after `.x1` downsampling).
    public struct Still: Sendable {
        public let image: CGImage
        public let pixelsPerPoint: CGFloat
    }

    public static func capture(_ selection: PickerSelection, scale: CaptureScale, windowShadow: Bool) async throws -> Still {
        let content = try await ShareableContentLoader.load()
        let config = SCStreamConfiguration()
        config.showsCursor = false

        let filter: SCContentFilter
        // Points captured, in the filter's own coordinate space: for a region this is the dragged rect (via
        // `sourceRect`), for a window or a full screen it is the filter's `contentRect`. Window mode with the
        // shadow on requests an oversized canvas instead (see below) because `contentRect` is the bare window
        // frame, not the frame plus shadow margins.
        let pointSize: CGSize
        // Set only for a window capture with the shadow on: how much bigger than `contentRect` the requested
        // canvas is, per side, so the result can be cropped back down after capture.
        var shadowMargin: CGFloat?
        switch selection {
        case .region(let screen, let rect):
            filter = try await displayFilter(for: screen.displayID, content: content)
            config.sourceRect = rect
            pointSize = rect.size
        case .screen(let screen):
            filter = try await displayFilter(for: screen.displayID, content: content)
            pointSize = filter.contentRect.size
        case .window(let pickerWindow):
            guard let window = content.windows.first(where: { $0.windowID == pickerWindow.id }) else {
                throw StillCaptureError(message: "Window is gone")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.ignoreShadowsSingleWindow = !windowShadow
            // Never back transparent pixels with white: the shadow (when kept) and the window's own transparent
            // areas both need to survive into the PNG untouched.
            config.shouldBeOpaque = false
            if windowShadow {
                // `contentRect` is the bare window frame; it does NOT include the shadow's margins (verified on
                // a real window: the shadow-on and shadow-off captures came back the same size when both used
                // `contentRect` directly, with the shadow-on one visibly squeezed to fit). Asking for exactly
                // `contentRect` here would force SCK to scale window+shadow down to fit that box. Ask for an
                // oversized canvas instead: with `scalesToFit` off, SCK renders the window (and its shadow) at
                // native scale anchored at the canvas's top-left, so the window body stays native size and the
                // shadow spills into the extra margin. `capture(...)` crops the result back to its actual
                // (non-transparent) bounds afterwards.
                config.scalesToFit = false
                let margin: CGFloat = 128
                shadowMargin = margin
                pointSize = CGSize(width: filter.contentRect.width + margin * 2, height: filter.contentRect.height + margin * 2)
            } else {
                pointSize = filter.contentRect.size
            }
        }

        // SCStreamConfiguration defaults width/height to 1920x1080, not the filter's native size: leaving them
        // unset scales the screenshot to that box instead of the display's real pixels. Always request native
        // pixels here; `.x1` downsamples afterwards so the two knobs (source resolution, output resolution)
        // stay independent, same as the recorder's `pixelsPerPoint`. No evenness rounding here (unlike the
        // recorder's `CaptureGeometry.outputSize`, which is a video-encoder rule): a still just wants the exact
        // pixel count the filter reports.
        let pixelScale = CGFloat(filter.pointPixelScale)
        let width = (pointSize.width * pixelScale).rounded()
        let height = (pointSize.height * pixelScale).rounded()
        config.width = Int(width)
        config.height = Int(height)

        var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        if shadowMargin != nil {
            // Off the main actor: scanning every row for the rightmost opaque pixel is real work the panel and
            // the next hotkey press should not wait on. `captured` is a `let` so the detached closure captures
            // a value, not a reference to the enclosing function's mutable `image`.
            let captured = image
            image = await Task.detached(priority: .utility) { Self.croppedToContent(captured) }.value
        }
        guard scale == .x1 else { return Still(image: image, pixelsPerPoint: pixelScale) }
        // Downscale off the image's own pixel dimensions, not `selection.pointSize`: a window capture's real
        // pixels (contentRect, shadow margins included) can differ from the picker's own frame.
        let oneXSize = CGSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale)
        return Still(image: try ImageWriter.downscale(image, to: oneXSize), pixelsPerPoint: 1)
    }

    /// Crops `image` to the bounding box of its non-transparent pixels (window plus shadow on an oversized
    /// canvas). Returns `image` unchanged if it is fully transparent or the scan fails.
    nonisolated static func croppedToContent(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1 else { return image }
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        // The context only borrows the buffer, so it is made, drawn into and scanned inside one closure.
        let bounds: CGRect? = data.withUnsafeMutableBytes { raw in
            // A bitmap context's buffer starts at the image's top row, the same origin `CGImage.cropping(to:)` uses.
            guard let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                let rowBase = y * bytesPerRow
                var first = -1
                for x in 0..<width where raw[rowBase + x * 4 + 3] != 0 {
                    first = x
                    break
                }
                guard first >= 0 else { continue }
                var last = width - 1
                while raw[rowBase + last * 4 + 3] == 0 { last -= 1 }
                minX = min(minX, first)
                maxX = max(maxX, last)
                if minY == height { minY = y }
                maxY = y
            }
            guard maxX >= 0 else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        guard let bounds else { return image }
        return image.cropping(to: bounds) ?? image
    }

    /// A whole display at native pixels, Deskpouch's own windows left out, no picker involved. The colour loupe
    /// samples from this.
    public static func display(_ displayID: CGDirectDisplayID) async throws -> Still {
        let content = try await ShareableContentLoader.load()
        let filter = try await displayFilter(for: displayID, content: content)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        let pixelScale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * pixelScale).rounded())
        config.height = Int((filter.contentRect.height * pixelScale).rounded())
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Still(image: image, pixelsPerPoint: pixelScale)
    }

    private static func displayFilter(for displayID: CGDirectDisplayID, content: SCShareableContent) async throws -> SCContentFilter {
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw StillCaptureError(message: "Display not found")
        }
        if let app = await ShareableContentLoader.ownApplication(fallback: content) {
            return SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        }
        return SCContentFilter(display: display, excludingWindows: [])
    }
}
