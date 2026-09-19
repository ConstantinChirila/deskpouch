import AVFoundation
import AppKit
import ImageIO
import DeskpouchCore
import Observation
import SwiftUI

/// The one player behind the preview: whichever recording is focused is loaded into it. Plays with sound.
@MainActor
@Observable
final class GalleryVideoPlayer {
    let player = AVPlayer()
    private(set) var url: URL?
    private(set) var isPlaying = false
    private(set) var time: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// The file could not be opened as a video.
    private(set) var failed = false

    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var seeking = false
    @ObservationIgnored private var pendingSeek: TimeInterval?

    init() {
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.time = min(time.seconds, self.duration)
                if self.duration > 0, time.seconds >= self.duration - 0.01 {
                    self.isPlaying = false
                }
            }
        }
    }

    /// Shows `url` paused on its first frame. The same file again changes nothing.
    func load(_ url: URL) {
        guard url != self.url else { return }
        stop()
        self.url = url
        failed = false
        let asset = AVURLAsset(url: url)
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        loadTask = Task { [weak self] in
            let seconds = (try? await asset.load(.duration))?.seconds
            guard let self, !Task.isCancelled, self.url == url else { return }
            if let seconds, seconds.isFinite, seconds > 0 {
                duration = seconds
            } else {
                failed = true
            }
        }
    }

    /// Another row took the preview, or the window closed.
    func stop() {
        loadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        url = nil
        isPlaying = false
        time = 0
        duration = 0
        pendingSeek = nil
    }

    func toggle() {
        guard url != nil, !failed else { return }
        if isPlaying {
            isPlaying = false
            player.pause()
            return
        }
        isPlaying = true
        // At the end: once more from the top.
        if duration > 0, time >= duration - 0.05 {
            time = 0
            Task { [weak self] in
                guard let self else { return }
                await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                if isPlaying { player.play() }
            }
        } else {
            player.play()
        }
    }

    /// Dragging the bar: pauses, and only ever waits for the newest position.
    func scrub(to fraction: Double) {
        guard duration > 0 else { return }
        if isPlaying {
            isPlaying = false
            player.pause()
        }
        time = min(max(0, fraction), 1) * duration
        pendingSeek = time
        guard !seeking else { return }
        seeking = true
        Task { [weak self] in
            while let self, let next = pendingSeek {
                pendingSeek = nil
                await player.seek(to: CMTime(seconds: next, preferredTimescale: 600_00), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            self?.seeking = false
        }
    }
}

/// A recording in the preview: the picture (click or Space plays), and a transport bar under it.
struct VideoPreview: View {
    let url: URL
    let video: GalleryVideoPlayer
    let thumbnails: ThumbnailCache

    var body: some View {
        VStack(spacing: 0) {
            if video.failed {
                Spacer()
                Text("This recording cannot be played").font(.dp(15, .semibold))
                Spacer()
            } else {
                PlayerSurface(player: video.player)
                    // The player layer is empty until its first frame arrives: the tile's frame stands in.
                    .background {
                        if let poster = thumbnails.image(for: url) {
                            Image(decorative: poster, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .blur(radius: 6)
                                .opacity(0.85)
                        }
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                    .onTapGesture { video.toggle() }
                    .overlay {
                        if !video.isPlaying, video.time == 0 {
                            PlayBadge().allowsHitTesting(false).transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: video.isPlaying)
                    .accessibilityElement()
                    .accessibilityLabel("Recording, \(video.isPlaying ? "playing" : "paused")")
                    .accessibilityAddTraits(.isButton)
                TransportBar(
                    isPlaying: video.isPlaying, time: video.time, duration: video.duration,
                    toggle: { video.toggle() }, scrub: { video.scrub(to: $0) }
                )
            }
        }
        .onAppear { video.load(url) }
        .onChange(of: url) { _, new in video.load(new) }
        .onDisappear { video.stop() }
    }

}

/// Play / pause, the time, a scrub bar and the length: the same strip under a recording and under a GIF.
struct TransportBar: View {
    let isPlaying: Bool
    let time: TimeInterval
    let duration: TimeInterval
    let toggle: @MainActor () -> Void
    let scrub: @MainActor (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Group {
                    if isPlaying {
                        PauseGlyph().fill(Theme.Colors.text)
                    } else {
                        PlayGlyph().fill(Theme.Colors.text)
                    }
                }
                .frame(width: 11, height: 12)
                .frame(width: 34, height: 28)
                .background(Capsule().fill(Theme.Colors.tint(0.07)))
                .overlay(Capsule().strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Text(TimeFormat.minutesSeconds(time))
                .frame(width: 38, alignment: .trailing)
            ScrubBar(fraction: duration > 0 ? time / duration : 0, scrub: scrub)
            Text(TimeFormat.minutesSeconds(duration))
                .frame(width: 38, alignment: .leading)
        }
        .font(.dp(12, .medium))
        .monospacedDigit()
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Theme.Colors.tint(0.03))
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.tint(0.08)).frame(height: 1) }
    }
}

/// A flat bar with an amber fill and a knob; press or drag anywhere on it.
private struct ScrubBar: View {
    let fraction: Double
    let scrub: @MainActor (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let x = width * min(max(0, fraction), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.tint(0.12)).frame(height: 4)
                Capsule().fill(Theme.Colors.accent).frame(width: x, height: 4)
                Circle()
                    .fill(Theme.Colors.text)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: x - 5.5)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { scrub(Double($0.location.x / width)) })
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

private struct PlayBadge: View {
    var body: some View {
        PlayGlyph()
            .fill(Theme.Colors.text)
            .frame(width: 20, height: 22)
            .offset(x: 2)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PauseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let bar = rect.width * 0.34
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: bar, height: rect.height), cornerSize: CGSize(width: 1, height: 1))
        path.addRoundedRect(in: CGRect(x: rect.maxX - bar, y: rect.minY, width: bar, height: rect.height), cornerSize: CGSize(width: 1, height: 1))
        return path
    }
}

/// A GIF played frame by frame, so it can be paused and scrubbed like a recording. Frames are decoded as they
/// are shown, never all at once: a long GIF is hundreds of megabytes unpacked.
@MainActor
@Observable
final class GalleryGIFPlayer {
    /// `CGImageSource` reads are safe from any thread; the type just does not say so.
    private final class Source: @unchecked Sendable {
        let source: CGImageSource
        init(_ source: CGImageSource) { self.source = source }

        func frame(_ index: Int) -> CGImage? {
            CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
    }

    private(set) var url: URL?
    private(set) var frame: CGImage?
    private(set) var isPlaying = false
    private(set) var time: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var failed = false

    @ObservationIgnored private var source: Source?
    /// When each frame starts, in seconds from the top; one more entry than frames would be `duration`.
    @ObservationIgnored private var starts: [TimeInterval] = []
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var loop: Task<Void, Never>?

    /// Shows `url` and starts playing it, as a GIF does everywhere else. The same file again changes nothing.
    func load(_ url: URL) {
        guard url != self.url else { return }
        stop()
        self.url = url
        failed = false
        Task { [weak self] in
            let opened = await Task.detached(priority: .userInitiated) { Self.open(url) }.value
            guard let self, self.url == url else { return }
            guard let opened else {
                failed = true
                return
            }
            source = opened.source
            starts = opened.starts
            duration = opened.duration
            frame = opened.first
            index = 0
            time = 0
            if opened.starts.count > 1 { play() }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        url = nil
        source = nil
        frame = nil
        starts = []
        isPlaying = false
        time = 0
        duration = 0
        index = 0
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    private func pause() {
        isPlaying = false
        loop?.cancel()
        loop = nil
    }

    private func play() {
        guard let source, starts.count > 1, !isPlaying else { return }
        isPlaying = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let shown = index
                let end = shown + 1 < starts.count ? starts[shown + 1] : duration
                try? await Task.sleep(for: .seconds(max(0.02, end - starts[shown])))
                if Task.isCancelled { return }
                let next = (shown + 1) % starts.count
                let image = await Task.detached(priority: .userInitiated) { source.frame(next) }.value
                if Task.isCancelled { return }
                index = next
                time = starts[next]
                if let image { frame = image }
            }
        }
    }

    /// Dragging the bar: pauses on the frame under the pointer.
    func scrub(to fraction: Double) {
        guard let source, !starts.isEmpty else { return }
        pause()
        let target = min(max(0, fraction), 1) * duration
        let wanted = max(0, (starts.firstIndex { $0 > target } ?? starts.count) - 1)
        time = starts[wanted]
        guard wanted != index else { return }
        index = wanted
        if let image = source.frame(wanted) { frame = image }
    }

    nonisolated private static func open(_ url: URL) -> (source: Source, starts: [TimeInterval], duration: TimeInterval, first: CGImage)? {
        guard let raw = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(raw)
        let source = Source(raw)
        guard count > 0, let first = source.frame(0) else { return nil }
        var starts: [TimeInterval] = []
        var total: TimeInterval = 0
        for index in 0..<count {
            starts.append(total)
            let properties = CGImageSourceCopyPropertiesAtIndex(raw, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            // Browsers treat anything under 20 ms as 100 ms; so does this.
            total += delay < 0.02 ? 0.1 : delay
        }
        return (source, starts, total, first)
    }
}

/// A GIF in the preview: at its native size (one pixel per screen pixel, only ever scaled down), looping, with
/// the same transport as a recording.
struct GIFPreview: View {
    let url: URL
    let gif: GalleryGIFPlayer
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            if gif.failed {
                Spacer()
                Text("This GIF cannot be read").font(.dp(15, .semibold))
                Spacer()
            } else {
                GeometryReader { geometry in
                    if let frame = gif.frame {
                        let native = CGSize(width: CGFloat(frame.width) / displayScale, height: CGFloat(frame.height) / displayScale)
                        let area = CGSize(width: max(1, geometry.size.width - 32), height: max(1, geometry.size.height - 32))
                        let fit = min(1, area.width / native.width, area.height / native.height)
                        Image(decorative: frame, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: native.width * fit, height: native.height * fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { gif.toggle() }
                .accessibilityElement()
                .accessibilityLabel("GIF, \(gif.isPlaying ? "playing" : "paused")")
                .accessibilityAddTraits(.isButton)
                TransportBar(
                    isPlaying: gif.isPlaying, time: gif.time, duration: gif.duration,
                    toggle: { gif.toggle() }, scrub: { gif.scrub(to: $0) }
                )
            }
        }
        .onAppear { gif.load(url) }
        .onChange(of: url) { _, new in gif.load(new) }
        .onDisappear { gif.stop() }
    }
}
