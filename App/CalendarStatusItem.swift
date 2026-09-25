import AppKit
import ToolCalendar

/// The calendar's own menubar item (plan 11), left of the pouch: "Design sync · in 12 min", amber in the last
/// 5 minutes, mint while the event runs. Hidden, not removed, while nothing is near, so it keeps its place.
@MainActor
final class CalendarStatusItem {
    private let item: NSStatusItem
    var onClick: ((NSStatusBarButton) -> Void)?

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked(_:))
        }
    }

    var button: NSStatusBarButton? { item.isVisible ? item.button : nil }

    func show(_ menubar: Agenda.Menubar?) {
        guard let menubar else {
            item.isVisible = false
            return
        }
        item.button?.image = CalendarMenubarImage.make(menubar)
        item.button?.setAccessibilityLabel("Calendar: \(menubar.text)")
        item.isVisible = true
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        onClick?(sender)
    }
}
