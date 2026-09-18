import AppKit

/// A borderless, transparent window covering one screen, above everything including full screen apps (the
/// screen-saver level, like the picker). Click-through by default, for marks drawn over the user's work (click
/// ripple, keystroke chip); `interactive` makes it take clicks everywhere, clear pixels included, and become key,
/// for the colour loupe.
@MainActor
public final class OverlayWindow: NSWindow {
    public init(screen: NSScreen, interactive: Bool) {
        self.interactive = interactive
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = interactive
        // Set explicitly: left at its default, AppKit passes clicks on clear pixels through to the app below.
        ignoresMouseEvents = !interactive
        setFrame(screen.frame, display: false)
    }

    private let interactive: Bool

    override public var canBecomeKey: Bool { interactive }
    override public var canBecomeMain: Bool { false }
}
