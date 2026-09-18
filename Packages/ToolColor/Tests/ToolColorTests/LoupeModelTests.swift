import CoreGraphics
import Foundation
import Testing
@testable import ToolColor

@MainActor
struct LoupeModelTests {
    /// A 2x screen 100x50 pt at the origin and a 1x screen to its right, AppKit global coordinates.
    let retina = LoupeScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 50), pixelsPerPoint: 2)
    let external = LoupeScreen(id: 2, frame: CGRect(x: 100, y: 0, width: 80, height: 60), pixelsPerPoint: 1)

    /// Every pixel encodes its own coordinates: red = x, green = y.
    func buffer(for screen: LoupeScreen) -> PixelBuffer {
        PixelBuffer(width: screen.pixelWidth, height: screen.pixelHeight, pixelsPerPoint: screen.pixelsPerPoint) { x, y in
            SRGBColor(bytes: UInt8(x), UInt8(y), 7)
        }
    }

    func model() -> LoupeModel {
        let model = LoupeModel(screens: [retina, external], settings: ColorSettings())
        model.setBuffer(buffer(for: retina), for: retina.id)
        return model
    }

    @Test func mouseMapsToTopLeftPixels() {
        let model = model()
        // 10.75 pt from the left, 0.25 pt below the top edge (y is bottom-up): pixel (21, 0).
        model.move(to: CGPoint(x: 10.75, y: 49.75))
        #expect(model.screenID == retina.id)
        #expect(model.pixel == PixelPoint(x: 21, y: 0))
        #expect(model.centerColor == SRGBColor(bytes: 21, 0, 7))
        #expect(model.value == "#150007")
    }

    @Test func gridIsCentredAndMarksOffScreenCells() throws {
        let model = model()
        model.move(to: CGPoint(x: 0.1, y: 49.9)) // pixel (0, 0), top-left corner
        let grid = model.grid
        #expect(grid.count == 121)
        // Row 5, column 5 is the centre; everything left of or above it is outside the screen.
        #expect(grid[5 * 11 + 5] == SRGBColor(bytes: 0, 0, 7))
        #expect(grid[5 * 11 + 4] == nil)
        #expect(grid[4 * 11 + 5] == nil)
        #expect(try #require(grid[10 * 11 + 10]) == SRGBColor(bytes: 5, 5, 7))
    }

    @Test func nudgeMovesWholePixelsAndReturnsTheirCentre() throws {
        let model = model()
        model.move(to: CGPoint(x: 10, y: 40)) // pixel (20, 20)
        let point = try #require(model.nudge(dx: 1, dy: -3))
        #expect(model.pixel == PixelPoint(x: 21, y: 17))
        // Pixel centre, back through the mapping, lands on the same pixel.
        #expect(point == CGPoint(x: 10.75, y: 50 - 8.75))
        model.move(to: point)
        #expect(model.pixel == PixelPoint(x: 21, y: 17))
    }

    @Test func nudgeStopsAtTheScreenEdge() {
        let model = model()
        model.move(to: CGPoint(x: 99.9, y: 0.1)) // bottom-right pixel (199, 99)
        _ = model.nudge(dx: 10, dy: 10)
        #expect(model.pixel == PixelPoint(x: 199, y: 99))
        _ = model.nudge(dx: -500, dy: -500)
        #expect(model.pixel == PixelPoint(x: 0, y: 0))
    }

    @Test func secondScreenLoadsLazily() {
        let model = model()
        let screen = model.move(to: CGPoint(x: 150, y: 30))
        #expect(screen?.id == external.id)
        #expect(model.pixel == PixelPoint(x: 50, y: 30))
        #expect(model.centerColor == nil)
        #expect(model.grid.isEmpty)
        model.setBuffer(buffer(for: external), for: external.id)
        #expect(model.centerColor == SRGBColor(bytes: 50, 30, 7))
    }

    @Test func pointOnTheOuterEdgeStaysOnTheNearestScreen() {
        let model = model()
        model.move(to: CGPoint(x: 180, y: 60)) // top-right corner of the external screen, outside its frame
        #expect(model.screenID == external.id)
        #expect(model.pixel == PixelPoint(x: 79, y: 0))
    }

    @Test func settingsDriveValueAndHint() {
        let model = model()
        model.move(to: CGPoint(x: 0.1, y: 49.9))
        model.settings.format = .rgb
        #expect(model.value == "rgb(0 0 7)")
        model.settings.tailwindHints = false
        #expect(model.match == nil)
    }

    @Test func layoutFlipsAboveNearTheBottomAndStaysInside() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let middle = LoupeLayout(center: CGPoint(x: 200, y: 100), bounds: bounds).readoutCenter
        #expect(middle.y > 100)
        let low = LoupeLayout(center: CGPoint(x: 200, y: 280), bounds: bounds).readoutCenter
        #expect(low.y < 280)
        let left = LoupeLayout(center: CGPoint(x: 2, y: 100), bounds: bounds).readoutCenter
        #expect(left.x - LoupeLayout.readoutSize.width / 2 >= 8)
    }
}

struct ColorSettingsTests {
    @Test func roundTripsThroughDefaults() throws {
        let name = "ColorSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ColorSettings.load(from: defaults) == ColorSettings())
        var settings = ColorSettings()
        settings.format = .oklch
        settings.tailwindHints = false
        settings.save(to: defaults)
        #expect(ColorSettings.load(from: defaults) == settings)
        #expect(settings.summary == "OKLCH")
        #expect(ColorSettings().summary == "Hex · Tailwind hints")
    }
}
