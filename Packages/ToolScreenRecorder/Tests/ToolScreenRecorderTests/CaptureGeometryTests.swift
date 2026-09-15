import CoreGraphics
import Testing
@testable import ToolScreenRecorder

struct CaptureGeometryTests {
    @Test func highQualityFitsRetinaDisplayInto1080Rows() {
        // 16" MacBook Pro: 1728x1117 points at 2x.
        let ppp = CaptureGeometry.pixelsPerPoint(displayPoints: CGSize(width: 1728, height: 1117), backingScale: 2, quality: .high)
        let full = CaptureGeometry.outputSize(points: CGSize(width: 1728, height: 1117), pixelsPerPoint: ppp)
        #expect(full.height == 1080)
        #expect(full.width == 1670)
    }

    @Test func highQualityLeavesSmallDisplaysAlone() {
        let ppp = CaptureGeometry.pixelsPerPoint(displayPoints: CGSize(width: 1440, height: 900), backingScale: 1, quality: .high)
        #expect(ppp == 1)
    }

    @Test func fullQualityIsNative() {
        let ppp = CaptureGeometry.pixelsPerPoint(displayPoints: CGSize(width: 1728, height: 1117), backingScale: 2, quality: .full)
        #expect(ppp == 2)
    }

    @Test func outputSizeIsEvenAndNeverBelowTwo() {
        #expect(CaptureGeometry.outputSize(points: CGSize(width: 101, height: 33), pixelsPerPoint: 1) == CGSize(width: 100, height: 32))
        #expect(CaptureGeometry.outputSize(points: CGSize(width: 1, height: 1), pixelsPerPoint: 0.5) == CGSize(width: 2, height: 2))
    }

    @Test func dragRectNormalisesAnyDirection() {
        let r = CaptureGeometry.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 160))
        #expect(r == CGRect(x: 40, y: 100, width: 60, height: 60))
    }

    @Test func aspectSnapStaysWithinTheDrag() {
        let r = CaptureGeometry.rect(from: .zero, to: CGPoint(x: 160, y: 160), aspect: 16.0 / 9.0)
        #expect(r.width == 160)
        #expect(r.height == 90)
        let tall = CaptureGeometry.rect(from: .zero, to: CGPoint(x: -20, y: 90), aspect: 16.0 / 9.0)
        #expect(tall == CGRect(x: -20, y: 0, width: 20, height: 11.25))
    }

    @Test func clampMovesAndShrinks() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(CaptureGeometry.clamped(CGRect(x: 90, y: -10, width: 30, height: 30), to: bounds) == CGRect(x: 70, y: 0, width: 30, height: 30))
        #expect(CaptureGeometry.clamped(CGRect(x: 0, y: 0, width: 300, height: 50), to: bounds).width == 100)
    }

    @Test func labels() {
        #expect(CaptureGeometry.dimensionLabel(CGSize(width: 1040, height: 760)) == "1040 × 760")
        #expect(CaptureGeometry.detail(points: CGSize(width: 1040, height: 760), frameRate: 60) == "1040 × 760 · 60 fps")
    }
}
