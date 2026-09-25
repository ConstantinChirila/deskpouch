import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ToolScreenshot

/// Renderer output against a checked-in PNG. Text is left out of the golden image (glyph rasterisation can shift
/// between macOS releases); `textDrawsItsPlate` covers text by sampling pixels instead.
///
/// To refresh the golden file after an intended drawing change:
/// `DESKPOUCH_RECORD_GOLDEN=1 swift test --filter AnnotationRendererTests`, then review the PNG.
@MainActor
struct AnnotationRendererTests {
    static let goldenName = "annotations-1x"

    /// 240x160 two-tone checker, so blur and shadows have something to change.
    func baseImage() -> CGImage {
        let width = 240, height = 160
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in stride(from: 0, to: height, by: 10) {
            for x in stride(from: 0, to: width, by: 10) {
                let on = (x / 10 + y / 10) % 2 == 0
                context.setFillColor(on ? CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
                                        : CGColor(srgbRed: 0.95, green: 0.95, blue: 0.9, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 10, height: 10))
            }
        }
        return context.makeImage()!
    }

    var model: [Annotation] {
        [
            // Fixed id: blur noise is seeded from it.
            Annotation(id: UUID(uuidString: "6F1C2A34-0B7E-4D5A-9C11-2E3F4A5B6C7D")!, shape: .blur(CGRect(x: 130, y: 20, width: 90, height: 60))),
            Annotation(shape: .box(CGRect(x: 20, y: 20, width: 80, height: 50)), color: .accent, size: .thin),
            Annotation(shape: .box(CGRect(x: 30, y: 90, width: 60, height: 50)), color: .ink, size: .thick),
            Annotation(shape: .arrow(from: CGPoint(x: 120, y: 140), to: CGPoint(x: 200, y: 100)), color: .white, size: .thick),
            Annotation(shape: .arrow(from: CGPoint(x: 110, y: 40), to: CGPoint(x: 60, y: 45)), color: .accent, size: .thin),
        ]
    }

    @Test func matchesGolden() throws {
        let renderer = AnnotationRenderer(base: baseImage(), pixelScale: 1)
        let image = try #require(renderer.render(model))
        #expect(image.width == 240 && image.height == 160)

        if ProcessInfo.processInfo.environment["DESKPOUCH_RECORD_GOLDEN"] != nil {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appending(path: "Golden/\(Self.goldenName).png")
            try writePNG(image, to: url)
            Issue.record("Recorded \(url.path); review it and run again without DESKPOUCH_RECORD_GOLDEN")
            return
        }
        let url = try #require(Bundle.module.url(forResource: Self.goldenName, withExtension: "png", subdirectory: "Golden"))
        let golden = try #require(loadImage(url))
        let (a, b) = (pixels(image), pixels(golden))
        #expect(a.count == b.count)
        // Tolerate anti-aliasing drift on edges, not a shape that moved.
        var differing = 0
        for i in 0..<min(a.count, b.count) where abs(Int(a[i]) - Int(b[i])) > 8 {
            differing += 1
        }
        #expect(differing <= a.count / 200, "\(differing) channel values differ from the golden image")
    }

    @Test func blurReplacesDetailInsideItsRectOnly() throws {
        let base = baseImage()
        let renderer = AnnotationRenderer(base: base, pixelScale: 2)
        let rect = CGRect(x: 0, y: 0, width: 120, height: 80)
        let image = try #require(renderer.render([Annotation(shape: .blur(rect))]))
        let (before, after) = (pixels(base), pixels(image))
        // Inside: 32 px blocks (16 pt at 2x) over a 10 px checker change some pixels.
        #expect(region(before, rect) != region(after, rect))
        // Outside: untouched.
        let outside = CGRect(x: 130, y: 90, width: 100, height: 60)
        #expect(region(before, outside) == region(after, outside))
    }

    @Test func blurBlocksAreUniformAndTheNoiseIsFixedPerMark() throws {
        let renderer = AnnotationRenderer(base: baseImage(), pixelScale: 1)
        // 16 px blocks: the second block row and column spans 16..<32.
        let mark = Annotation(shape: .blur(CGRect(x: 0, y: 0, width: 96, height: 64)))
        let first = pixels(try #require(renderer.render([mark])))
        let block = region(first, CGRect(x: 16, y: 16, width: 16, height: 16))
        let firstPixel = Array(block[0..<4])
        var uniform = true
        for i in stride(from: 0, to: block.count, by: 4) where Array(block[i..<i + 4]) != firstPixel {
            uniform = false
        }
        #expect(uniform)
        #expect(pixels(try #require(renderer.render([mark]))) == first)

        let other = Annotation(shape: .blur(CGRect(x: 0, y: 0, width: 96, height: 64)))
        let second = pixels(try #require(renderer.render([other])))
        let area = CGRect(x: 0, y: 0, width: 96, height: 64)
        #expect(region(first, area) != region(second, area))
    }

    @Test func pixelatingKeepsTheImagesColourSpace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(
            data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
            space: p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // A red outside sRGB: a trip through another colour space would not give these bytes back.
        context.setFillColor(try #require(CGColor(colorSpace: p3, components: [1, 0.1, 0.1, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let base = try #require(context.makeImage())
        let pixelated = try #require(AnnotationRenderer.pixelate(base, block: 16))
        #expect(pixelated.colorSpace?.name == CGColorSpace.displayP3)

        let bytes = try #require(pixelated.dataProvider?.data as Data?)
        let source = try #require(base.dataProvider?.data as Data?)
        for channel in 0..<3 {
            #expect(abs(Int(bytes[channel]) - Int(source[channel])) <= 1)
        }
    }

    @Test func textDrawsItsPlate() throws {
        let renderer = AnnotationRenderer(base: baseImage(), pixelScale: 1)
        let mark = Annotation(shape: .text(origin: CGPoint(x: 20, y: 20), string: "Hi"), color: .white)
        let plate = renderer.metrics.bounds(of: mark)
        #expect(plate.width > 20 && plate.height > 16)
        let image = try #require(renderer.render([mark]))
        let data = pixels(image)
        // Just inside the top-left corner, clear of the rounded corner and the glyphs: plate white.
        let x = Int(plate.minX) + 3, y = Int(plate.minY) + 3
        let i = (y * 240 + x) * 4
        #expect(data[i] > 245 && data[i + 1] > 245 && data[i + 2] > 245)
    }

    @Test func emptyModelRendersTheBase() throws {
        let base = baseImage()
        let image = try #require(AnnotationRenderer(base: base, pixelScale: 1).render([]))
        #expect(pixels(image) == pixels(base))
    }

    // MARK: Helpers

    /// RGBA8, top row first.
    func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    func region(_ data: [UInt8], _ rect: CGRect) -> [UInt8] {
        var out: [UInt8] = []
        for y in Int(rect.minY)..<Int(rect.maxY) {
            let start = (y * 240 + Int(rect.minX)) * 4
            out.append(contentsOf: data[start..<start + Int(rect.width) * 4])
        }
        return out
    }

    func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
