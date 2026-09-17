import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageWriterError: LocalizedError {
    let message: String
    public var errorDescription: String? { message }
}

/// File format for `ImageWriter.write`.
public enum ImageFormat: Sendable {
    case png
    /// `quality` is 0 to 1, ImageIO's `kCGImageDestinationLossyCompressionQuality`.
    case jpeg(quality: CGFloat)

    fileprivate var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }
}

/// PNG and JPEG encoding through ImageIO, and Lanczos downscaling through CoreImage. Core has its own small
/// ImageIO wrapper for history thumbnails (`HistoryThumbnails`); this one is Capture's, for full-size exports
/// and the 1x scale option, so neither package has to depend on the other for a few lines of ImageIO.
public enum ImageWriter {
    /// Writes `image` to `url` in `format`. The file's UTI comes from `format`, not from `url`'s extension.
    public static func write(_ image: CGImage, to url: URL, format: ImageFormat) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw ImageWriterError(message: "Could not create an image destination for \(url.lastPathComponent)")
        }
        try add(image, format: format, to: destination)
    }

    /// Resizes `image` to `size` (in pixels) with `CILanczosScaleTransform`. Used for the 1x scale option
    /// (downsampling to one pixel per point) and for thumbnails.
    public static func downscale(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let width = max(1, size.width.rounded())
        let height = max(1, size.height.rounded())
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            throw ImageWriterError(message: "CILanczosScaleTransform unavailable")
        }
        let ciImage = CIImage(cgImage: image)
        let scaleY = height / CGFloat(image.height)
        let aspectRatio = (width / CGFloat(image.width)) / scaleY
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scaleY, forKey: kCIInputScaleKey)
        filter.setValue(aspectRatio, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else {
            throw ImageWriterError(message: "CILanczosScaleTransform produced no output")
        }
        let context = CIContext()
        guard let scaled = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            throw ImageWriterError(message: "Could not render the downscaled image")
        }
        return scaled
    }

    private static func add(_ image: CGImage, format: ImageFormat, to destination: CGImageDestination) throws {
        var options: [CFString: Any] = [:]
        if case .jpeg(let quality) = format {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageWriterError(message: "Image encode failed")
        }
    }
}
