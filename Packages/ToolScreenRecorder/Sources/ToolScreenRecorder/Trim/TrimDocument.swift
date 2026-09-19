import AVFoundation
import AppKit
import DeskpouchCore
import Observation
import SwiftUI
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "trim")

/// The Trim editor for one recording: a player, in and out points, and the export as a cut mp4 (no re-encode) or
/// a GIF. Export writes beside the source and never touches the original.
@MainActor
@Observable
public final class TrimDocument: EditorDocument {
    enum Format: String, CaseIterable, Sendable {
        case mp4, gif

        var label: String { self == .mp4 ? "MP4" : "GIF" }
    }

    /// What the editor needs to know about the file before it opens. Loaded off the main actor by the caller.
    public struct Media: Sendable {
        let duration: TimeInterval
        let frameRate: Double
        let pixelSize: CGSize
        let fileSize: Int

        public static func load(_ url: URL) async throws -> Media {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw TrimExportError.noVideoTrack }
            let duration = try await asset.load(.duration).seconds
            let (natural, transform, rate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
            let size = natural.applying(transform)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            guard duration.isFinite, duration > 0 else { throw TrimExportError.cannotRead(nil) }
            return Media(
                duration: duration, frameRate: Double(rate),
                pixelSize: CGSize(width: abs(size.width), height: abs(size.height)), fileSize: bytes
            )
        }
    }

    /// A GIF longer than this gets the amber size warning. Export is still allowed.
    static let gifWarningLength: TimeInterval = 15

    public let sourceURL: URL
    let toolID: String
    let media: Media
    let player: AVPlayer

    private(set) var model: TrimModel
    var format: Format = .mp4 {
        didSet { if format != oldValue { refreshEstimate() } }
    }
    private(set) var isPlaying = false
    /// Evenly spaced frames for the filmstrip; empty until they are read.
    private(set) var thumbnails: [CGImage] = []
    /// Bytes per twelfth of a second, measured by exporting a short probe of this recording.
    private(set) var gifBytesPerTick: Double?
    /// 0...1 while a GIF is being written.
    private(set) var exportProgress: Double?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var estimateTask: Task<Void, Never>?
    @ObservationIgnored private var seeking = false
    @ObservationIgnored private var pendingSeek: TimeInterval?

    public init(sourceURL: URL, media: Media, toolID: String) {
        self.sourceURL = sourceURL
        self.media = media
        self.toolID = toolID
        model = TrimModel(duration: media.duration, frameRate: media.frameRate)
        player = AVPlayer(url: sourceURL)
        player.actionAtItemEnd = .pause
        observePlayback()
        loadThumbnails()
    }

    // MARK: EditorDocument

    public var title: String { "Trim" }

    /// One window per file: trimming an open file again brings its window forward.
    public var documentKey: String? { "trim:" + sourceURL.standardizedFileURL.path }

    public var subtitle: String {
        let state = model.isTrimmed ? "keeping \(TrimModel.label(model.selectedDuration)) of \(TrimModel.label(model.duration))" : "original saved"
        return "\(sourceURL.lastPathComponent) · \(state)"
    }

    public var unsavedChanges: UnsavedChanges? {
        guard model.isTrimmed else { return nil }
        return UnsavedChanges(
            title: "Discard this trim?",
            detail: "The recording itself is already saved and stays as it is. Export saves the trimmed part as a copy next to it."
        )
    }

    public var idealContentSize: CGSize {
        // Recordings are 2x or downscaled to 1080p; half the pixels is close enough to a 1:1 look.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return CGSize(
            width: max(560, media.pixelSize.width / scale),
            height: media.pixelSize.height / scale + TrimView.timelineBlockHeight
        )
    }

    public func makeContent() -> AnyView {
        AnyView(TrimView(document: self))
    }

    public func makeToolbar() -> AnyView {
        AnyView(TrimToolbar(document: self))
    }

    /// Writes the cut to Deskpouch's own folder and puts that file on the pasteboard. Nothing is saved to the
    /// user's folder and nothing is logged.
    public func copy() {
        pause()
        let destination = ScreenRecorderTool.stagingURL(for: Date())
            .deletingLastPathComponent()
            .appending(path: Self.exportURL(for: sourceURL, format: format, trimmed: model.isTrimmed).lastPathComponent)
        Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await write(to: destination)
                SystemOutputEffects().copyFile(destination)
            } catch {
                log.error("copy failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func export() async throws -> ToolResult? {
        pause()
        let destination = CaptureNaming.unique(Self.exportURL(for: sourceURL, format: format, trimmed: model.isTrimmed))
        let length = model.selectedDuration
        try await write(to: destination)
        return ToolResult(toolID: toolID, fileURL: destination, duration: length, kind: .recording)
    }

    private func write(to destination: URL) async throws {
        let range = model.start...model.end
        let source = sourceURL
        switch format {
        case .mp4:
            try await MP4Exporter.export(source, range: range, to: destination)
        case .gif:
            exportProgress = 0
            defer { exportProgress = nil }
            // Weak and main-actor bound, so the writer's thread can hand fractions back.
            let report: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor in
                    if self?.exportProgress != nil { self?.exportProgress = fraction }
                }
            }
            _ = try await Task.detached(priority: .userInitiated) {
                try await GIFExporter.export(source, range: range, to: destination, progress: report)
            }.value
        }
    }

    public func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.isSubset(of: .shift) else { return false }
        switch event.keyCode {
        case 49: // space
            togglePlayback()
            return true
        case 123, 124: // left, right: one frame, ten with Shift
            step(frames: (event.keyCode == 123 ? -1 : 1) * (flags.contains(.shift) ? 10 : 1))
            return true
        default:
            break
        }
        guard flags.isEmpty else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "i":
            markIn()
            return true
        case "o":
            markOut()
            return true
        default:
            return false
        }
    }

    public func close() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        thumbnailTask?.cancel()
        estimateTask?.cancel()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Playback

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Plays the kept part: from the playhead when it is inside, from the in point otherwise.
    func play() {
        if model.playhead < model.start || model.playhead >= model.end - model.frameDuration {
            model.seek(to: model.start)
        }
        isPlaying = true
        Task { [weak self] in
            guard let self else { return }
            await player.seek(to: Self.time(model.playhead), toleranceBefore: .zero, toleranceAfter: .zero)
            if isPlaying { player.play() }
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        player.pause()
    }

    private func observePlayback() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                if time.seconds >= self.model.end {
                    self.pause()
                    self.show(self.model.end)
                } else {
                    self.model.seek(to: time.seconds)
                }
            }
        }
    }

    /// Moves the playhead and the picture. Seeks are exact, one at a time: a drag only ever waits for the newest.
    private func show(_ time: TimeInterval) {
        model.seek(to: time)
        pendingSeek = model.playhead
        guard !seeking else { return }
        seeking = true
        Task { [weak self] in
            while let self, let next = pendingSeek {
                pendingSeek = nil
                await player.seek(to: Self.time(next), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            self?.seeking = false
        }
    }

    private static func time(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600_00)
    }

    // MARK: Editing

    func scrub(to time: TimeInterval) {
        pause()
        show(time)
    }

    /// Dragging a handle shows the frame it sits on.
    func dragStart(to time: TimeInterval) {
        pause()
        model.setStart(time)
        show(model.start)
    }

    func dragEnd(to time: TimeInterval) {
        pause()
        model.setEnd(time)
        show(model.end)
    }

    func handleDragFinished() {
        refreshEstimate()
    }

    func step(frames: Int) {
        pause()
        model.step(frames: frames)
        show(model.playhead)
    }

    func markIn() {
        model.markIn()
        refreshEstimate()
    }

    func markOut() {
        model.markOut()
        refreshEstimate()
    }

    // MARK: Filmstrip

    /// How many tiles fill a strip about a window wide, given the video's shape.
    static func thumbnailCount(aspect: CGFloat) -> Int {
        let tile = TrimView.stripHeight * max(0.2, aspect)
        return min(30, max(6, Int((1000 / tile).rounded(.up))))
    }

    private func loadThumbnails() {
        let url = sourceURL
        let duration = media.duration
        let aspect = media.pixelSize.height > 0 ? media.pixelSize.width / media.pixelSize.height : 16.0 / 9
        let count = Self.thumbnailCount(aspect: aspect)
        thumbnailTask = Task { [weak self] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            let height = TrimView.stripHeight * 2
            generator.maximumSize = CGSize(width: height * aspect, height: height)
            // The middle of each tile's share of the recording. Nearest keyframe is fine for a strip this small.
            let times = (0..<count).map { Self.time(duration * (Double($0) + 0.5) / Double(count)) }
            var images: [CGImage] = []
            for await result in generator.images(for: times) {
                if Task.isCancelled { return }
                // A frame that cannot be read repeats its neighbour, so the tiles stay where they belong.
                if case .success(_, let image, _) = result {
                    images.append(image)
                } else if let last = images.last {
                    images.append(last)
                }
            }
            self?.thumbnails = images
        }
    }

    // MARK: Estimate

    /// Size of the export as it stands, nil while the GIF probe has not run.
    var estimatedBytes: Int? {
        switch format {
        case .mp4:
            return Int(Double(media.fileSize) * model.selectedDuration / model.duration)
        case .gif:
            guard let gifBytesPerTick else { return nil }
            return Int(gifBytesPerTick * (model.selectedDuration * GIFExporter.framesPerSecond).rounded())
        }
    }

    var gifIsLong: Bool { format == .gif && model.selectedDuration > Self.gifWarningLength }

    /// GIF size depends on what is on screen, so it is measured: up to a second from the in point is written to
    /// a temporary file and scaled up.
    private func refreshEstimate() {
        estimateTask?.cancel()
        guard format == .gif else { return }
        let source = sourceURL
        let start = model.start
        let end = min(model.end, start + 1)
        estimateTask = Task { [weak self] in
            // Let a run of I / O presses or a format flip settle first.
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let perTick = await Task.detached(priority: .utility) { () -> Double? in
                let probe = FileManager.default.temporaryDirectory.appending(path: "deskpouch-gif-probe-\(UUID().uuidString).gif")
                defer { try? FileManager.default.removeItem(at: probe) }
                guard let output = try? await GIFExporter.export(source, range: start...end, to: probe),
                      let bytes = (try? FileManager.default.attributesOfItem(atPath: probe.path)[.size] as? NSNumber)?.doubleValue
                else { return nil }
                return bytes / Double(output.ticks)
            }.value
            if Task.isCancelled { return }
            self?.gifBytesPerTick = perTick
        }
    }

    // MARK: Helpers

    /// `Recording 2026-09-19 14.05.02.mp4` -> `… trimmed.mp4` or `… trimmed.gif` in the same folder; a GIF of the
    /// whole recording is just `… .gif`. Trimming a trimmed file does not stack the suffix; `CaptureNaming.unique`
    /// numbers it instead.
    static func exportURL(for source: URL, format: Format, trimmed: Bool) -> URL {
        var base = source.deletingPathExtension().lastPathComponent
        if let range = base.range(of: #" trimmed( \d+)?$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        let name = trimmed || format == .mp4 ? "\(base) trimmed" : base
        return source.deletingLastPathComponent().appending(path: "\(name).\(format.rawValue)")
    }
}
