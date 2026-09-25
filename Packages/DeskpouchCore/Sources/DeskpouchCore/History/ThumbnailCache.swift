import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Observation

/// First-second frames of recorded files, or the decoded thumbnail JPEG for image results, for the Recent tiles
/// and the gallery. Generated on demand off the main actor, a few at a time, and the most recently used are kept
/// in memory. Missing or unreadable files stay nil, so the row shows the dark placeholder.
@MainActor
@Observable
public final class ThumbnailCache {
    typealias Generator = @Sendable (URL, CGSize) async -> CGImage?

    private var images: [URL: CGImage] = [:]
    /// When each image was last asked for, as a value of `clock`: the smallest goes first. Not observed, so a
    /// hit redraws nothing.
    @ObservationIgnored private var lastUse: [URL: UInt64] = [:]
    @ObservationIgnored private var clock: UInt64 = 0
    /// Waiting or being generated.
    @ObservationIgnored private var pending: Set<URL> = []
    /// Requests without a free slot yet. The newest starts first: it is the one most likely still on screen.
    @ObservationIgnored private var waiting: [URL] = []
    @ObservationIgnored private var running = 0
    /// When each file last failed to give an image.
    @ObservationIgnored private var failed: [URL: Date] = [:]
    /// Forgotten while being generated: what that generation finds is already out of date, and is dropped.
    @ObservationIgnored private var forgottenInFlight: Set<URL> = []
    /// Bumped by `removeAll`, so a generation started before it does not put its image back.
    @ObservationIgnored private var epoch = 0

    /// Pixel size cap for the panel: its tile is 44x30 points, so this is crisp at 2x with room to crop.
    public nonisolated static let panelSize = CGSize(width: 176, height: 120)
    /// Images kept by default. A gallery thumbnail is about 220 KB, so this is about 45 MB at most.
    public nonisolated static let defaultCountLimit = 200
    /// Generations running at once; a fast scroll queues the rest.
    nonisolated static let maxConcurrent = 4
    /// A file that gave no image is tried again after this long, e.g. once its save has landed.
    nonisolated static let failedRetryInterval: TimeInterval = 30

    private let maximumSize: CGSize
    private let countLimit: Int
    private let now: () -> Date
    private let generator: Generator

    public convenience init(maximumSize: CGSize = ThumbnailCache.panelSize, countLimit: Int = ThumbnailCache.defaultCountLimit) {
        self.init(maximumSize: maximumSize, countLimit: countLimit, now: Date.init) { await ThumbnailCache.generate($0, maximumSize: $1) }
    }

    /// `now` and `generator` are for tests.
    init(maximumSize: CGSize, countLimit: Int, now: @escaping () -> Date, generator: @escaping Generator) {
        self.maximumSize = maximumSize
        self.countLimit = max(1, countLimit)
        self.now = now
        self.generator = generator
    }

    /// Returns the thumbnail when it is ready, and queues generating it when it is not.
    public func image(for url: URL) -> CGImage? {
        if let image = images[url] {
            clock += 1
            lastUse[url] = clock
            return image
        }
        guard !pending.contains(url) else { return nil }
        if let failedAt = failed[url] {
            guard now().timeIntervalSince(failedAt) >= Self.failedRetryInterval else { return nil }
            failed[url] = nil
        }
        pending.insert(url)
        waiting.append(url)
        // Scrolled past long ago: dropped, and asked for again if it comes back on screen.
        if waiting.count > countLimit { pending.remove(waiting.removeFirst()) }
        startWaiting()
        return nil
    }

    /// Waiting or being generated right now. For tests.
    func isPending(_ url: URL) -> Bool { pending.contains(url) }

    /// Drops what is known about `url`: a deleted row's image, or a missing file that should be tried again.
    public func forget(_ url: URL) {
        if images[url] != nil { images[url] = nil }
        lastUse[url] = nil
        failed[url] = nil
        if pending.contains(url), !waiting.contains(url) { forgottenInFlight.insert(url) }
    }

    /// Drops everything, e.g. when the window showing the thumbnails closes.
    public func removeAll() {
        epoch += 1
        if !images.isEmpty { images = [:] }
        lastUse = [:]
        failed = [:]
        pending = []
        waiting = []
        forgottenInFlight = []
    }

    private func startWaiting() {
        while running < Self.maxConcurrent, let url = waiting.popLast() {
            running += 1
            let size = maximumSize
            let generator = generator
            let epoch = epoch
            Task { [weak self] in
                let image = await generator(url, size)
                self?.finished(url, image: image, epoch: epoch)
            }
        }
    }

    private func finished(_ url: URL, image: CGImage?, epoch: Int) {
        running -= 1
        defer { startWaiting() }
        guard epoch == self.epoch else { return }
        pending.remove(url)
        guard forgottenInFlight.remove(url) == nil else { return }
        guard let image else {
            let date = now()
            failed = failed.filter { date.timeIntervalSince($0.value) < Self.failedRetryInterval }
            failed[url] = date
            return
        }
        clock += 1
        lastUse[url] = clock
        var kept = images
        kept[url] = image
        while kept.count > countLimit, let oldest = lastUse.min(by: { $0.value < $1.value })?.key {
            kept[oldest] = nil
            lastUse[oldest] = nil
        }
        images = kept
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
