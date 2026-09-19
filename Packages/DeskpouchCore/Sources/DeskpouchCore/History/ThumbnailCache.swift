import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Observation

/// First-second frames of recorded files, or the decoded thumbnail JPEG for image results, for the Recent tiles
/// and the gallery. Generated on demand off the main actor, kept in memory for the app's lifetime. Missing or unreadable files
/// stay nil, so the row shows the dark placeholder.
@MainActor
@Observable
public final class ThumbnailCache {
    private var images: [URL: CGImage] = [:]
    @ObservationIgnored private var pending: Set<URL> = []
    @ObservationIgnored private var failed: Set<URL> = []

    /// Pixel size cap for the panel: its tile is 44x30 points, so this is crisp at 2x with room to crop.
    public nonisolated static let panelSize = CGSize(width: 176, height: 120)

    private let maximumSize: CGSize

    public init(maximumSize: CGSize = ThumbnailCache.panelSize) {
        self.maximumSize = maximumSize
    }

    /// Returns the thumbnail when it is ready, and starts generating it the first time it is asked for.
    public func image(for url: URL) -> CGImage? {
        if let image = images[url] { return image }
        guard !pending.contains(url), !failed.contains(url) else { return nil }
        pending.insert(url)
        let size = maximumSize
        Task { [weak self] in
            let image = await Self.generate(url, maximumSize: size)
            guard let self else { return }
            pending.remove(url)
            if let image { images[url] = image } else { failed.insert(url) }
        }
        return nil
    }

    /// Lets a file that was missing be tried again, e.g. after a save landed.
    public func forget(_ url: URL) {
        images[url] = nil
        failed.remove(url)
    }

    /// Extensions decoded directly through ImageIO instead of `AVAssetImageGenerator`: `HistoryThumbnails.write`
    /// always writes a screenshot's cached thumbnail as one of these, and a plain image file has no video track
    /// for the generator to seek into anyway. A GIF gives its first frame.
    nonisolated private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif"]

    nonisolated private static func generate(_ url: URL, maximumSize: CGSize) async -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            return loadImage(url, maximumSize: maximumSize)
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.isNumeric ? min(1, duration.seconds / 2) : 0
            let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            return image
        } catch {
            return nil
        }
    }

    /// Thumbnail-only decode: a full-size screenshot can be tens of megapixels, and this tile only ever shows
    /// `maximumSize` of it. `kCGImageSourceCreateThumbnailFromImageAlways` builds one even when the file has no
    /// embedded thumbnail (a PNG never does); ImageIO downsamples during decode instead of after, so the full
    /// resolution is never materialised in memory.
    nonisolated private static func loadImage(_ url: URL, maximumSize: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(maximumSize.width, maximumSize.height)),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
