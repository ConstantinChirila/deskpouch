import AppKit
import ScreenCaptureKit

/// ScreenCaptureKit lookups every capture tool needs before it opens the picker.
@MainActor
public enum ShareableContentLoader {
    /// On-screen displays and windows, desktop windows left out.
    public static func load() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    /// Deskpouch itself, for excluding its own windows from a capture. The general content list leaves out apps
    /// without regular windows, Deskpouch included, so this asks the current-process query first.
    public static func ownApplication(fallback: SCShareableContent) async -> SCRunningApplication? {
        let pid = ProcessInfo.processInfo.processIdentifier
        if let own = try? await SCShareableContent.currentProcess, let app = own.applications.first(where: { $0.processID == pid }) {
            return app
        }
        return fallback.applications.first { $0.processID == pid }
    }

    /// Screens from AppKit, windows from ScreenCaptureKit in front-to-back order, toolbar on the mouse's screen.
    public static func makeModel(
        from content: SCShareableContent, systemAudio: Bool, microphone: Bool, frameRate: Int, style: PickerStyle = .record
    ) -> PickerModel {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouse = NSEvent.mouseLocation
        var toolbarScreenID = 0
        let screens = NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            if screen.frame.contains(mouse) { toolbarScreenID = index }
            return PickerScreen(
                id: index,
                displayID: CGDirectDisplayID(number?.uint32Value ?? 0),
                frame: screen.frame,
                cgFrame: CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                                width: screen.frame.width, height: screen.frame.height),
                backingScale: screen.backingScaleFactor
            )
        }

        let order = windowZOrder()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = content.windows
            .filter { window in
                window.isOnScreen && window.windowLayer == 0
                    && window.owningApplication?.processID != ownPID
                    && window.frame.width >= 40 && window.frame.height >= 40
            }
            .sorted { (order[$0.windowID] ?? .max) < (order[$1.windowID] ?? .max) }
            .map { window in
                PickerWindow(
                    id: window.windowID, frame: window.frame,
                    title: window.title ?? "", appName: window.owningApplication?.applicationName ?? ""
                )
            }

        return PickerModel(
            screens: screens, windows: windows, toolbarScreenID: toolbarScreenID,
            systemAudio: systemAudio, microphone: microphone, frameRate: frameRate, style: style
        )
    }

    /// Window id to z index, front-most first. ScreenCaptureKit's list has no documented order.
    private static func windowZOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        for (index, info) in list.enumerated() {
            if let number = info[kCGWindowNumber as String] as? NSNumber {
                order[CGWindowID(number.uint32Value)] = index
            }
        }
        return order
    }
}
