import AppKit
import CoreGraphics

/// Clipboard and paste-into-frontmost-app. Posting ⌘V needs Accessibility access.
@MainActor
public enum Paster {
    public static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Sends ⌘V to whatever app is frontmost. Returns that app's name, or nil when the event could not be posted.
    @discardableResult
    public static func pasteIntoFrontmostApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let target = app.localizedName else {
            return nil
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),   // kVK_ANSI_V
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return nil
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return target
    }
}
