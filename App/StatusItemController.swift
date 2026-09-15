import AppKit
import DeskpouchCore

/// The menubar item. Idle glyph, an amber meter pill while listening, a pink timer pill while recording.
@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    private var meter = LevelHistory(count: 7)
    var onClick: ((NSStatusBarButton) -> Void)?

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked(_:))
            button.setAccessibilityLabel("Deskpouch")
        }
    }

    var button: NSStatusBarButton? { item.button }

    func showIdle() {
        meter.reset()
        item.button?.image = MenubarIcon.idle()
    }

    func beginListening() {
        meter.reset()
        item.button?.image = MenubarIcon.listening(levels: meter.bars)
    }

    func showRecording(elapsed: TimeInterval) {
        item.button?.image = MenubarIcon.recording(elapsed: elapsed)
    }

    func push(level: Float, dt: TimeInterval) {
        meter.push(level: level, dt: dt)
        item.button?.image = MenubarIcon.listening(levels: meter.bars)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        onClick?(sender)
    }
}
