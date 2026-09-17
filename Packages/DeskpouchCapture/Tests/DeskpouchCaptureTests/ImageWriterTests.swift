import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import DeskpouchCapture

struct ImageWriterTests {
    /// A solid-colour bitmap of the given size, for tests that only care about dimensions and round-tripping.
    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func pngRoundTripsThroughAFile() throws {
        let image = makeImage(width: 12, height: 8)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageWriter.write(image, to: url, format: .png)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        let read = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        #expect(read?.width == 12)
        #expect(read?.height == 8)
    }

    @Test func pixelsPerPointRoundTripsAsDPI() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageWriter.write(makeImage(width: 4, height: 4), to: url, format: .png, pixelsPerPoint: 2)
        #expect(ImageWriter.pixelsPerPoint(of: url) == 2)
    }

    @Test func downscaleHitsTheExactTargetSize() throws {
        let image = makeImage(width: 200, height: 100)
        let scaled = try ImageWriter.downscale(image, to: CGSize(width: 100, height: 50))
        #expect(scaled.width == 100)
        #expect(scaled.height == 50)
    }

    @Test func downscaleToOneXMatchesPointSizeNotJustHalving() throws {
        // A 2x capture (240x160 px) downsampled to 1x for a 120x80pt selection.
        let image = makeImage(width: 240, height: 160)
        let scaled = try ImageWriter.downscale(image, to: CGSize(width: 120, height: 80))
        #expect(scaled.width == 120)
        #expect(scaled.height == 80)
    }

}
