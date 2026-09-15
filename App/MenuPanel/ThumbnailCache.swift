import AVFoundation
import CoreGraphics
import Foundation
import Observation

/// First-second frames of recorded files for the Recent tiles. Generated on demand off the main actor, kept in
/// memory for the app's lifetime. Missing or unreadable files stay nil, so the row shows the dark placeholder.
@MainActor
@Observable
final class ThumbnailCache {
    private var images: [URL: CGImage] = [:]
    @ObservationIgnored private var pending: Set<URL> = []
    @ObservationIgnored private var failed: Set<URL> = []

    /// Pixel size cap; the tile is 44x30 points so this is crisp at 2x with room to crop.
    nonisolated static let maximumSize = CGSize(width: 176, height: 120)

    /// Returns the thumbnail when it is ready, and starts generating it the first time it is asked for.
    func image(for url: URL) -> CGImage? {
        if let image = images[url] { return image }
        guard !pending.contains(url), !failed.contains(url) else { return nil }
        pending.insert(url)
        Task { [weak self] in
            let image = await Self.generate(url)
            guard let self else { return }
            pending.remove(url)
            if let image { images[url] = image } else { failed.insert(url) }
        }
        return nil
    }

    /// Lets a file that was missing be tried again, e.g. after a save landed.
    func forget(_ url: URL) {
        images[url] = nil
        failed.remove(url)
    }

    nonisolated private static func generate(_ url: URL) async -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
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
}
