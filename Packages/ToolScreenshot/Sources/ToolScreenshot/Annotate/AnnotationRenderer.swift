import AppKit
import CoreGraphics
import CoreText
import DeskpouchCore

/// Draws annotations with Core Graphics. The canvas calls `draw(_:in:)` on a context already scaled to image
/// pixels; export calls `render(_:)`. One drawing path, so the file matches the screen.
///
/// Every drawing call expects a y-down context (origin top-left, image pixels), the way SwiftUI's `Canvas` hands
/// one over; `render` flips its bitmap context to match.
///
/// Holds only immutable, Sendable state and touches no main-actor API (the font is resolved to a name up front),
/// so it is built and used for export off the main actor.
public final class AnnotationRenderer: Sendable {
    public let base: CGImage
    public let metrics: AnnotationMetrics
    /// The whole image pixelated once; blur marks show it through a clip, so every blur shares one grid.
    private let pixelated: CGImage?
    /// PostScript name of the text face, nil for the system font.
    private let fontName: String?

    public var imageSize: CGSize { CGSize(width: base.width, height: base.height) }

    /// Pixelates the whole image: real work for a large capture, so build it off the main actor.
    /// `fontName` comes from `textFontName` (main actor).
    public init(base: CGImage, pixelScale: CGFloat, fontName: String? = nil) {
        self.base = base
        self.fontName = fontName
        metrics = AnnotationMetrics(pixelScale: pixelScale) { string, fontSize in
            Self.measure(string, fontSize: fontSize, fontName: fontName)
        }
        pixelated = Self.pixelate(base, block: metrics.blurBlock)
    }

    /// The app's semibold face (Geist) when it is registered, else nil for the system font. System fonts are
    /// not looked up by name: their private names do not round-trip through `CTFontCreateWithName`.
    @MainActor
    public static var textFontName: String? {
        let name = Fonts.nsFont(12, .semibold).fontName
        return name.hasPrefix(".") ? nil : name
    }

    /// Base image plus marks, full size. Nil only if a bitmap context could not be made.
    public func render(_ annotations: [Annotation]) -> CGImage? {
        let width = base.width
        let height = base.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: base.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) ?? CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(annotations, in: context)
        return context.makeImage()
    }

    /// Draws `annotations` in order onto a y-down context in image pixels.
    public func draw(_ annotations: [Annotation], in context: CGContext) {
        for annotation in annotations {
            context.saveGState()
            draw(annotation, in: context)
            context.restoreGState()
        }
    }

    private func draw(_ annotation: Annotation, in context: CGContext) {
        let color = Self.fill(annotation.color)
        let lineWidth = metrics.lineWidth(annotation.size)
        switch annotation.shape {
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, lineWidth: lineWidth, color: color, in: context)

        case .box(let rect):
            guard rect.width > 0, rect.height > 0 else { return }
            setShadow(in: context)
            let radius = min(4 * metrics.pixelScale, rect.width / 2, rect.height / 2)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            context.setLineJoin(.round)
            context.strokePath()

        case .blur(let rect):
            guard rect.width > 0, rect.height > 0, let pixelated else { return }
            context.clip(to: rect)
            context.saveGState()
            drawImage(pixelated, in: context)
            context.restoreGState()
            drawNoise(over: rect, seed: annotation.id, in: context)

        case .text(let origin, let string):
            guard !string.isEmpty else { return }
            let plate = metrics.textPlate(string, origin: origin, size: annotation.size)
            setShadow(in: context)
            let radius = 5 * metrics.pixelScale
            context.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(color)
            context.fillPath()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            drawText(
                string, fontSize: metrics.fontSize(annotation.size), color: Self.ink(on: annotation.color),
                at: CGPoint(x: plate.minX + metrics.textInset.width, y: plate.minY + metrics.textInset.height),
                in: context
            )

        case .badge(let center, let number):
            let diameter = metrics.badgeDiameter(annotation.size)
            let disc = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            setShadow(in: context)
            context.setFillColor(color)
            context.fillEllipse(in: disc)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            // A thin contrasting ring keeps a badge readable on a background of its own colour.
            context.setStrokeColor(Self.ink(on: annotation.color).copy(alpha: 0.35) ?? color)
            context.setLineWidth(max(1, metrics.pixelScale))
            context.strokeEllipse(in: disc.insetBy(dx: metrics.pixelScale / 2, dy: metrics.pixelScale / 2))
            let label = "\(number)"
            let fontSize = diameter * 0.52
            let size = Self.measure(label, fontSize: fontSize, fontName: fontName)
            drawText(
                label, fontSize: fontSize, color: Self.ink(on: annotation.color),
                at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), in: context
            )
        }
    }

    private func drawArrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat, color: CGColor, in context: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let ux = dx / length
        let uy = dy / length
        // Head scales with the stroke but never swallows a short arrow.
        let headLength = min(lineWidth * 4.5, length * 0.6)
        let headWidth = headLength * 0.9
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        let left = CGPoint(x: base.x - uy * headWidth / 2, y: base.y + ux * headWidth / 2)
        let right = CGPoint(x: base.x + uy * headWidth / 2, y: base.y - ux * headWidth / 2)

        setShadow(in: context)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.move(to: from)
        // Stop the shaft inside the head so its round cap does not poke past the point.
        context.addLine(to: CGPoint(x: base.x + ux * headLength * 0.3, y: base.y + uy * headLength * 0.3))
        context.strokePath()
        context.setLineJoin(.round)
        context.setLineWidth(lineWidth * 0.5)
        context.move(to: to)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.drawPath(using: .fillStroke)
        context.endTransparencyLayer()
    }

    /// Soft drop shadow so marks separate from busy screenshots.
    private func setShadow(in context: CGContext) {
        // Shadow offsets are in base space (y up) regardless of the CTM, so a positive y would point up here.
        context.setShadow(
            offset: CGSize(width: 0, height: -1 * metrics.pixelScale),
            blur: 4 * metrics.pixelScale,
            color: CGColor(gray: 0, alpha: 0.35)
        )
    }

    /// Lightens or darkens each blur block by a random amount fixed per mark (seeded from its id, so the canvas and
    /// the export agree). Averaged blocks of text can be matched against rendered fonts; the noise breaks that.
    private func drawNoise(over rect: CGRect, seed: UUID, in context: CGContext) {
        let block = metrics.blurBlock
        let seedValue = withUnsafeBytes(of: seed.uuid) { $0.load(as: UInt64.self) }
        let firstColumn = Int((rect.minX / block).rounded(.down))
        let lastColumn = Int((rect.maxX / block).rounded(.up))
        let firstRow = Int((rect.minY / block).rounded(.down))
        let lastRow = Int((rect.maxY / block).rounded(.up))
        for row in firstRow..<lastRow {
            for column in firstColumn..<lastColumn {
                let random = Self.mix(seedValue ^ UInt64(bitPattern: Int64(column &* 73_856_093 ^ row &* 19_349_663)))
                let amount = CGFloat(random % 1000) / 1000 * 0.22
                let light = random >> 32 & 1 == 0
                context.setFillColor(CGColor(gray: light ? 1 : 0, alpha: amount))
                context.fill(CGRect(x: CGFloat(column) * block, y: CGFloat(row) * block, width: block, height: block))
            }
        }
    }

    /// SplitMix64 finaliser: a well-spread hash of one integer.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Draws an image into a y-down context without flipping it.
    private func drawImage(_ image: CGImage, in context: CGContext) {
        let height = CGFloat(image.height)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: height))
    }

    /// `origin` is the top-left of the text's line box in the y-down context.
    private func drawText(_ string: String, fontSize: CGFloat, color: CGColor, at origin: CGPoint, in context: CGContext) {
        let line = Self.line(string, fontSize: fontSize, fontName: fontName, color: color)
        var ascent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        context.saveGState()
        // Glyphs are drawn y-up; flip the text matrix so they come out upright in the y-down context.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: origin.x, y: origin.y + ascent)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func font(size: CGFloat, name: String?) -> CTFont {
        if let name { return CTFontCreateWithName(name as CFString, size, nil) }
        return CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    static func line(_ string: String, fontSize: CGFloat, fontName: String?, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: fontSize, name: fontName),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// Line box of `string`: typographic width, ascent plus descent.
    static func measure(_ string: String, fontSize: CGFloat, fontName: String?) -> CGSize {
        let line = line(string, fontSize: fontSize, fontName: fontName, color: CGColor(gray: 0, alpha: 1))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        return CGSize(width: ceil(width), height: ceil(ascent + descent))
    }

    static func fill(_ color: AnnotationColor) -> CGColor {
        switch color {
        case .accent: CGColor(srgbRed: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255, alpha: 1)
        case .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .ink: CGColor(srgbRed: 0x1C / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1)
        }
    }

    /// Text colour on a fill of `color`.
    static func ink(on color: AnnotationColor) -> CGColor {
        color == .ink ? fill(.white) : fill(.ink)
    }

    /// Averages the image into `block`-sized squares on a grid anchored at its top-left corner: downsample into a
    /// small bitmap (area-averaging), then scale back up with no interpolation. Returns a full-size image.
    static func pixelate(_ image: CGImage, block: CGFloat) -> CGImage? {
        let width = image.width
        let height = image.height
        let step = max(1, block)
        let columns = Int((CGFloat(width) / step).rounded(.up))
        let rows = Int((CGFloat(height) / step).rounded(.up))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        func bitmap(_ width: Int, _ height: Int, _ space: CGColorSpace) -> CGContext? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
        }
        // The image's own space (Display P3 for a real capture), as `render` uses: a round trip through another
        // one would shift the colours of a blurred region against its surroundings.
        var space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var made: CGContext?
        if let own = image.colorSpace, own.supportsOutput, let context = bitmap(columns, rows, own) {
            space = own
            made = context
        }
        guard let small = made ?? bitmap(columns, rows, space) else { return nil }
        small.interpolationQuality = .high
        let scaledHeight = CGFloat(height) / step
        // Bitmap contexts are y-up: pin the image to the top row so blocks line up with the image's top-left.
        small.draw(image, in: CGRect(x: 0, y: CGFloat(rows) - scaledHeight, width: CGFloat(width) / step, height: scaledHeight))
        guard let averaged = small.makeImage(), let full = bitmap(width, height, space) else { return nil }
        full.interpolationQuality = .none
        let blocksHeight = CGFloat(rows) * step
        full.draw(averaged, in: CGRect(x: 0, y: CGFloat(height) - blocksHeight, width: CGFloat(columns) * step, height: blocksHeight))
        return full.makeImage()
    }
}
