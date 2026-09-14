import AppKit
import DeskpouchCore

/// Explicit entry point. `@main` on an NSApplicationDelegate runs NSApplicationMain, which expects a nib and never
/// instantiates the delegate.
@main
@MainActor
enum DeskpouchMain {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: Shell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.registerBundled()
        installMainMenu()
        let shell = Shell()
        shell.start()
        self.shell = shell
    }

    func applicationWillTerminate(_ notification: Notification) {
        shell?.stop()
    }

    /// LSUIElement apps show no menubar, but a main menu is what makes ⌘Q work while our panel is key.
    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Deskpouch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }
}
