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

    /// Called on every meter tick while listening, so other meters (menubar, panel) can follow.
    @ObservationIgnored public var onLevel: (@MainActor (Float, TimeInterval) -> Void)?

    @ObservationIgnored private let panel = OverlayPanel()
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var levelProvider: LevelProvider?
    @ObservationIgnored private var autoHide: Task<Void, Never>?

    /// Canvas around the pill so shadows and the transcribing card have room.
    static let canvasSize = CGSize(width: 560, height: 200)
    static let bottomInset: CGFloat = 48
    static let tickInterval: TimeInterval = 1 / 30

    public init() {
        let hosting = NSHostingView(rootView: PillRoot(controller: self))
        hosting.frame = CGRect(origin: .zero, size: Self.canvasSize)
        panel.contentView = hosting
        panel.setContentSize(Self.canvasSize)
    }

    /// Listening state with a 30 fps meter pulled from `levelProvider`.
    public func showListening(levelProvider: @escaping LevelProvider) {
        meter.reset()
        startedAt = Date()
        lastTick = startedAt
        elapsed = 0
        self.levelProvider = levelProvider
        show(.listening)
        ticker?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Any state. Cancels a pending auto-hide; stops the meter unless listening.
    public func show(_ newState: PillState) {
        autoHide?.cancel()
        autoHide = nil
        if !newState.isListening { stopTicker() }
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

    private func tick() {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? Self.tickInterval
        lastTick = now
        let level = levelProvider?() ?? 0
        meter.push(level: level, dt: dt)
        if let startedAt { elapsed = now.timeIntervalSince(startedAt) }
        onLevel?(level, dt)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        levelProvider = nil
        startedAt = nil
    }

    /// Bottom-centre of the screen under the mouse, canvas bottom above the dock.
    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - Self.canvasSize.width / 2,
            y: visible.minY + 8
        )
        panel.setFrameOrigin(origin)
    }
}
