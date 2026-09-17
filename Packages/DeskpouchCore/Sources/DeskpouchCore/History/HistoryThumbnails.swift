import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "history")

/// Writes and removes the small JPEG thumbnails history keeps for image results, so Recent and History can
/// show a tile without decoding the original file. Core has no dependency on Capture's `ImageWriter`, so this
/// is its own small ImageIO wrapper.
public enum HistoryThumbnails {
    /// `~/Library/Application Support/Deskpouch/thumbs`. Tests pass their own directory instead.
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Deskpouch", directoryHint: .isDirectory)
            .appending(path: "thumbs", directoryHint: .isDirectory)
    }

    /// Longest edge of a generated thumbnail, in pixels.
    static let maxDimension: CGFloat = 240

    /// Downscales `image` to fit `maxDimension` on its long edge and writes it as JPEG under `directory`, named
    /// after `id`. Returns the written file's URL, or nil if the write failed (directory not creatable, encode
    /// failure); a missing thumbnail is not worth failing the whole history write over.
    public static func write(_ image: CGImage, id: UUID, to directory: URL = defaultDirectory) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log.error("thumbs directory create failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        let url = directory.appending(path: "\(id.uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        let longEdge = CGFloat(max(image.width, image.height))
        let scale = longEdge > maxDimension ? maxDimension / longEdge : 1
        guard let thumbnail = flatten(image, scale: scale) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        CGImageDestinationAddImage(destination, thumbnail, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    /// Removes a previously written thumbnail. No-op if the file is already gone.
    public static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Downscales `image` by `scale` (1 keeps its size) onto an opaque white background. Always runs, even at
    /// scale 1: JPEG has no alpha channel, so a screenshot's transparent edges (a window capture with the shadow
    /// on) would otherwise be backfilled black by the encoder instead of reading as the panel's own background.
    private static func flatten(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
