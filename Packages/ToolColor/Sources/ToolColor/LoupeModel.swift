import AppKit
import Observation

/// One screen the loupe can sit on. `frame` is AppKit global (bottom-left origin).
struct LoupeScreen: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let pixelsPerPoint: CGFloat

    /// Pixel under a global point, top-left origin.
    func pixel(at point: CGPoint) -> PixelPoint {
        PixelPoint(
            x: Int(((point.x - frame.minX) * pixelsPerPoint).rounded(.down)),
            y: Int(((frame.maxY - point.y) * pixelsPerPoint).rounded(.down))
        )
    }

    /// Centre of a pixel as a global point, for warping the cursor onto it.
    func globalPoint(of pixel: PixelPoint) -> CGPoint {
        CGPoint(
            x: frame.minX + (CGFloat(pixel.x) + 0.5) / pixelsPerPoint,
            y: frame.maxY - (CGFloat(pixel.y) + 0.5) / pixelsPerPoint
        )
    }

    /// Centre of a pixel in this screen's view coordinates (top-left origin, points).
    func localPoint(of pixel: PixelPoint) -> CGPoint {
        CGPoint(x: (CGFloat(pixel.x) + 0.5) / pixelsPerPoint, y: (CGFloat(pixel.y) + 0.5) / pixelsPerPoint)
    }

    var pixelWidth: Int { Int((frame.width * pixelsPerPoint).rounded()) }
    var pixelHeight: Int { Int((frame.height * pixelsPerPoint).rounded()) }
}

struct PixelPoint: Equatable, Hashable, Sendable {
    var x: Int
    var y: Int
}

/// Where the loupe is and what it reads. The controller feeds it mouse moves and nudges; the view draws it.
@MainActor
@Observable
final class LoupeModel {
    /// Cells per side of the magnified grid. Odd, so one cell is the centre.
    nonisolated static let gridSize = 11

    let screens: [LoupeScreen]
    var settings: ColorSettings
    /// Display captures, filled in as each one arrives.
    private(set) var buffers: [CGDirectDisplayID: PixelBuffer] = [:]
    /// The screen and pixel under the (hidden) cursor.
    private(set) var screenID: CGDirectDisplayID?
    private(set) var pixel = PixelPoint(x: 0, y: 0)

    init(screens: [LoupeScreen], settings: ColorSettings) {
        self.screens = screens
        self.settings = settings
    }

    var screen: LoupeScreen? {
        screens.first { $0.id == screenID }
    }

    func setBuffer(_ buffer: PixelBuffer, for id: CGDirectDisplayID) {
        buffers[id] = buffer
    }

    /// Follows the mouse. Returns the screen it is on now, so the caller can start a capture for a new one.
    @discardableResult
    func move(to point: CGPoint) -> LoupeScreen? {
        guard let target = screens.first(where: { $0.frame.contains(point) }) ?? nearestScreen(to: point) else { return nil }
        screenID = target.id
        pixel = clamp(target.pixel(at: point), to: target)
        return target
    }

    /// Arrow keys: moves by whole pixels, stays on the current screen. Returns the global point to warp the
    /// cursor to, so the next mouse move continues from here instead of jumping back.
    func nudge(dx: Int, dy: Int) -> CGPoint? {
        guard let screen else { return nil }
        pixel = clamp(PixelPoint(x: pixel.x + dx, y: pixel.y + dy), to: screen)
        return screen.globalPoint(of: pixel)
    }

    /// The pixel under the cursor, or nil while its display is still being captured.
    var centerColor: SRGBColor? {
        guard let screenID, let buffer = buffers[screenID] else { return nil }
        return buffer.color(x: pixel.x, y: pixel.y)
    }

    /// `gridSize`² cells, row by row from the top left. Empty while loading; nil cells fall outside the screen.
    var grid: [SRGBColor?] {
        guard let screenID, let buffer = buffers[screenID] else { return [] }
        let half = Self.gridSize / 2
        var cells: [SRGBColor?] = []
        cells.reserveCapacity(Self.gridSize * Self.gridSize)
        for y in (pixel.y - half)...(pixel.y + half) {
            for x in (pixel.x - half)...(pixel.x + half) {
                cells.append(buffer.color(x: x, y: y))
            }
        }
        return cells
    }

    /// What a click copies.
    var value: String? {
        centerColor.map { settings.format.string(for: $0) }
    }

    var match: TailwindPalette.Match? {
        guard settings.tailwindHints, let centerColor else { return nil }
        return TailwindPalette.nearest(to: centerColor)
    }

    private func clamp(_ pixel: PixelPoint, to screen: LoupeScreen) -> PixelPoint {
        PixelPoint(
            x: min(max(pixel.x, 0), screen.pixelWidth - 1),
            y: min(max(pixel.y, 0), screen.pixelHeight - 1)
        )
    }

    /// A point exactly on a screen's top or right edge is outside `frame` (half-open); keep it on the closest one.
    private func nearestScreen(to point: CGPoint) -> LoupeScreen? {
        screens.min { a, b in distance(point, a.frame) < distance(point, b.frame) }
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
