import CoreGraphics
import DeskpouchCapture
import Testing
@testable import ToolScreenRecorder

struct RecorderGeometryTests {
    func pixelsPerPoint(_ points: CGSize, scale: CGFloat, _ quality: RecorderSettings.Quality) -> CGFloat {
        CaptureGeometry.pixelsPerPoint(displayPoints: points, backingScale: scale, maxHeight: quality.maxPixelHeight)
    }

    @Test func highQualityFitsRetinaDisplayInto1080Rows() {
        // 16" MacBook Pro: 1728x1117 points at 2x.
        let ppp = pixelsPerPoint(CGSize(width: 1728, height: 1117), scale: 2, .high)
        let full = CaptureGeometry.outputSize(points: CGSize(width: 1728, height: 1117), pixelsPerPoint: ppp)
        #expect(full.height == 1080)
        #expect(full.width == 1670)
    }

    @Test func highQualityLeavesSmallDisplaysAlone() {
        #expect(pixelsPerPoint(CGSize(width: 1440, height: 900), scale: 1, .high) == 1)
    }

    @Test func fullQualityIsNative() {
        #expect(pixelsPerPoint(CGSize(width: 1728, height: 1117), scale: 2, .full) == 2)
    }

    @MainActor
    @Test func pillDetail() {
        #expect(ScreenRecorderTool.pillDetail(points: CGSize(width: 1040, height: 760), frameRate: 60) == "1040 × 760 · 60 fps")
    }
}
