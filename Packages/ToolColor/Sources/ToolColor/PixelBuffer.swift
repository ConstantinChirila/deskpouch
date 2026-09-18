import CoreGraphics

/// A display capture redrawn into 8-bit sRGB, top row first, so sampling is an array read and the values are
/// already what a hex code means. Drawing into the sRGB context is what converts from the display's own
/// colour space (Display P3 on recent Macs).
struct PixelBuffer: Sendable {
    let width: Int
    let height: Int
    let pixelsPerPoint: CGFloat
    private let bytes: [UInt8]

    init?(image: CGImage, pixelsPerPoint: CGFloat) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.pixelsPerPoint = pixelsPerPoint
        self.bytes = bytes
    }

    /// Test fixture: `color(x, y)` for every pixel.
    init(width: Int, height: Int, pixelsPerPoint: CGFloat, color: (Int, Int) -> SRGBColor) {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let b = color(x, y).bytes
                let i = (y * width + x) * 4
                bytes[i] = b.red
                bytes[i + 1] = b.green
                bytes[i + 2] = b.blue
                bytes[i + 3] = 255
            }
        }
        self.width = width
        self.height = height
        self.pixelsPerPoint = pixelsPerPoint
        self.bytes = bytes
    }

    /// Nil outside the capture.
    func color(x: Int, y: Int) -> SRGBColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return SRGBColor(bytes: bytes[i], bytes[i + 1], bytes[i + 2])
    }
}
