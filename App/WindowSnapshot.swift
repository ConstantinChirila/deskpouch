import AppKit
import ScreenCaptureKit

/// Screenshot of one of our own windows through ScreenCaptureKit. Design review only: unlike a view cache it
/// includes Core Animation effects (the panel's spring-in scale and fade) and costs milliseconds, not seconds.
enum WindowSnapshot {
    @MainActor
    static func capture(windowNumber: Int) async -> NSImage? {
        guard let content = try? await SCShareableContent.currentProcess,
              let window = content.windows.first(where: { $0.windowID == CGWindowID(windowNumber) }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            return nil
        }
        return NSImage(cgImage: image, size: window.frame.size)
    }
}
