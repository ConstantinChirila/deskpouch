import CoreGraphics
import Testing
@testable import DeskpouchCapture

struct StillCaptureTests {
    /// A transparent canvas with one opaque block. `block` is in CoreGraphics coordinates, origin bottom-left.
    private func makeImage(width: Int, height: Int, block: CGRect?) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        if let block {
            context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
            context.fill(block)
        }
        return context.makeImage()!
    }

    /// Alpha of every pixel, top row first.
    private func alphas(of image: CGImage) -> [UInt8] {
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<image.width * image.height).map { pixels[$0 * 4 + 3] }
    }

    @Test func cropsATransparentMarginAway() {
        // Uneven margins, so a crop measured from the wrong edge would land on transparent rows.
        let image = makeImage(width: 40, height: 30, block: CGRect(x: 5, y: 4, width: 20, height: 10))
        let cropped = StillCapture.croppedToContent(image)
        #expect(cropped.width == 20)
        #expect(cropped.height == 10)
        #expect(alphas(of: cropped).allSatisfy { $0 == 255 })
    }

    @Test func aFullyTransparentImageIsLeftAlone() {
        let image = makeImage(width: 16, height: 12, block: nil)
        let cropped = StillCapture.croppedToContent(image)
        #expect(cropped.width == 16)
        #expect(cropped.height == 12)
    }
}
