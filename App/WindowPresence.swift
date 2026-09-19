import AppKit
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "presence")

/// Deskpouch lives in the menubar (accessory: no Dock icon, not in ⌘Tab). While a real window is open (an editor,
/// the gallery) it becomes a regular app so the window can be found again, and goes back when the last one closes.
@MainActor
final class WindowPresence {
    private var open = 0

    /// One call per window group opening (true) or closing (false).
    func changed(_ isOpen: Bool) {
        open = max(0, open + (isOpen ? 1 : -1))
        let policy: NSApplication.ActivationPolicy = open > 0 ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let ok = NSApp.setActivationPolicy(policy)
        log.info("activation policy -> \(policy == .regular ? "regular" : "accessory", privacy: .public) ok=\(ok)")
    }
}
