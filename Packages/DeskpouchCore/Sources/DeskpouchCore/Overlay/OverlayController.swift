import AppKit
import Observation
import SwiftUI
import os

private let overlayLog = Logger(subsystem: "com.constantinchirila.deskpouch", category: "overlay")

/// Owns the floating pill: one panel, one state, one meter. Tools push state; the shell positions it.
@MainActor
@Observable
public final class OverlayController {
    public typealias LevelProvider = @MainActor () -> Float

    public private(set) var state: PillState = .hidden
    public let meter = LevelMeterModel(barCount: 25)
    public private(set) var elapsed: TimeInterval = 0
    /// Window size. The default canvas leaves room for shadows; while recording it shrinks to the pill so the
    /// clickable window covers as little of the screen as possible.
    private(set) var canvasSize = OverlayController.defaultCanvasSize

    /// Called on every meter tick while listening, so other meters (menubar, panel) can follow.
    @ObservationIgnored public var onLevel: (@MainActor (Float, TimeInterval) -> Void)?

    @ObservationIgnored private let panel = OverlayPanel()
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var levelProvider: LevelProvider?
    @ObservationIgnored private var autoHide: Task<Void, Never>?
    @ObservationIgnored private var stopHandler: (@MainActor () -> Void)?

    /// Canvas around the pill so shadows have room. The pill sits at the top of the canvas; the shadow falls below it.
    static let defaultCanvasSize = CGSize(width: 560, height: 140)
    static let topInset: CGFloat = 12
    /// Gap between the menubar and the pill.
    static let menubarGap: CGFloat = 10
    /// Room either side of the recording pill for its ring and glow.
    static let recordingMargin: CGFloat = 24
    static let tickInterval: TimeInterval = 1 / 30

    public init() {
        let hosting = NSHostingView(rootView: PillRoot(controller: self))
        hosting.frame = CGRect(origin: .zero, size: Self.defaultCanvasSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setContentSize(Self.defaultCanvasSize)
    }

    /// Listening state with a 30 fps meter pulled from `levelProvider`.
    public func showListening(levelProvider: @escaping LevelProvider) {
        meter.reset()
        self.levelProvider = levelProvider
        show(.listening)
        startTicker(since: Date())
    }

    /// Recording state: timer counted from `since`, Stop button calling `onStop`. The pill takes clicks in this state.
    public func showRecording(detail: String, since: Date = Date(), onStop: @escaping @MainActor () -> Void) {
        stopHandler = onStop
        show(.recording(detail: detail))
        startTicker(since: since)
    }

    /// Replaces the recording detail line without restarting the timer.
    public func updateRecording(detail: String) {
        guard state.isRecording else { return }
        state = .recording(detail: detail)
    }

    func stopRequested() {
        stopHandler?()
    }

    /// Any state. Cancels a pending auto-hide; stops the ticker unless the state is timed.
    public func show(_ newState: PillState) {
        autoHide?.cancel()
        autoHide = nil
        if !newState.isTimed { stopTicker() }
        if !newState.isRecording { stopHandler = nil }
        panel.ignoresMouseEvents = !newState.isRecording
        canvasSize = Self.canvasSize(for: newState)
        panel.setContentSize(canvasSize)
        place()
        panel.alphaValue = 1
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        withAnimation(.easeOut(duration: 0.2)) {
            state = newState
        }
        overlayLog.info("show \(String(describing: newState), privacy: .public)")
    }

    /// Shows a state, then hides after `delay`. Used for "pasted" and errors.
    public func flash(_ newState: PillState, for delay: Duration = .seconds(1.2)) {
        show(newState)
        autoHide = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    public func hide() {
        autoHide?.cancel()
        autoHide = nil
        stopTicker()
        overlayLog.info("hide")
        withAnimation(.easeOut(duration: 0.16)) {
            state = .hidden
        }
        // Let the SwiftUI exit transition play, then take the window off screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.state == .hidden else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Renders the live panel content through AppKit. Design review only.
    public func debugSnapshot() -> NSImage? {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func startTicker(since: Date) {
        startedAt = since
        lastTick = Date()
        elapsed = Date().timeIntervalSince(since)
        ticker?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? Self.tickInterval
        lastTick = now
        if let startedAt {
            let next = now.timeIntervalSince(startedAt)
            // The recording pill only shows whole seconds; skip redraws in between.
            if state.isListening || Int(next) != Int(elapsed) { elapsed = next }
        }
        guard let levelProvider else { return }
        let level = levelProvider()
        meter.push(level: level, dt: dt)
        onLevel?(level, dt)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        levelProvider = nil
        startedAt = nil
    }

    /// The recording pill gets a window just wide enough for its widest timer; everything else gets the full canvas.
    private static func canvasSize(for state: PillState) -> CGSize {
        guard case .recording(let detail) = state else { return defaultCanvasSize }
        let probe = NSHostingView(rootView: RecordingPill(elapsed: 5999, detail: detail, stop: {}))
        let width = probe.fittingSize.width + 2 * recordingMargin
        return CGSize(width: max(width, 200), height: topInset + 52 + 56)
    }

    /// Screen point of the pill's centre, for hit-test checks in demos.
    public var debugPillCenter: CGPoint {
        CGPoint(x: panel.frame.midX, y: panel.frame.maxY - Self.topInset - 26)
    }

    /// Top-centre of the screen under the mouse, just under the menubar: away from chat inputs and terminals,
    /// which live at the bottom of most windows.
    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - canvasSize.width / 2,
            y: visible.maxY - Self.menubarGap + Self.topInset - canvasSize.height
        )
        panel.setFrameOrigin(origin)
    }
}
