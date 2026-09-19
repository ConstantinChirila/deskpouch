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

    /// Hidden while Deskpouch is an accessory app, where it is still what makes ⌘Q work with the panel key. It shows
    /// once a real window turns the app regular (`WindowPresence`). The windows take their own keys first
    /// (`performKeyEquivalent`), so Edit's items only reach text fields and views that answer the selectors.
    private func installMainMenu() {
        let menu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Deskpouch", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Deskpouch", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Deskpouch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            menu.addItem(item)
        }
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }
}
