import AppKit
import Observation
import SwiftUI
import os

private let overlayLog = Logger(subsystem: "com.constantinchirila.deskpouch", category: "overlay")

/// Owns the floating pill: one panel, one state, one meter. Tools push state; the shell positions it.
@MainActor
@Observable
public final class OverlayController {
    public private(set) var state: PillState = .hidden
    public let meter = LevelMeterModel(barCount: 25)
    public private(set) var elapsed: TimeInterval = 0

    @ObservationIgnored private let panel = OverlayPanel()
    @ObservationIgnored private var startedAt: Date?

    /// Canvas around the pill so shadows and the transcribing card have room.
    static let canvasSize = CGSize(width: 560, height: 160)
    static let bottomInset: CGFloat = 48

    public init() {
        let hosting = NSHostingView(rootView: PillRoot(controller: self))
        hosting.frame = CGRect(origin: .zero, size: Self.canvasSize)
        panel.contentView = hosting
        panel.setContentSize(Self.canvasSize)
    }

    public func showListening() {
        meter.reset()
        startedAt = Date()
        elapsed = 0
        place()
        // The window animator does not reliably fade a freshly ordered-in panel; SwiftUI animates the content instead.
        panel.alphaValue = 1
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        withAnimation(.easeOut(duration: 0.16)) {
            state = .listening
        }
        overlayLog.info("show listening: frame=\(String(describing: self.panel.frame), privacy: .public) visible=\(self.panel.isVisible) alpha=\(self.panel.alphaValue)")
    }

    public func hide() {
        overlayLog.info("hide")
        withAnimation(.easeOut(duration: 0.16)) {
            state = .hidden
        }
        startedAt = nil
        // Let the SwiftUI exit transition play, then take the window off screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.state == .hidden else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Feed a raw level (0...1) after `dt` seconds. Drives the meter and the timer.
    public func push(level: Float, dt: TimeInterval) {
        meter.push(level: level, dt: dt)
        if let startedAt {
            elapsed = Date().timeIntervalSince(startedAt)
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

    /// Bottom-centre of the screen under the mouse, canvas bottom `bottomInset` above the dock.
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
