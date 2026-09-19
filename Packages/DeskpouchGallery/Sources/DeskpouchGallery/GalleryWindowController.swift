import AppKit
import DeskpouchCore
import Observation
import SwiftUI

/// What the gallery hands back to the app: the things only the shell and the tools know how to do.
public struct GalleryActions {
    public var copy: @MainActor (HistoryItem) -> Void
    public var reveal: @MainActor (HistoryItem) -> Void
    /// Annotate for a screenshot, Trim for a recording.
    public var edit: @MainActor (HistoryItem) -> Void
    /// "Annotate", "Trim", or nil when the row has no editor (or its file is gone).
    public var editLabel: @MainActor (HistoryItem) -> String?
    /// Every format of a colour row, as (label, value) lines. The conversions live with the colour tool.
    public var colorFormats: @MainActor (HistoryItem) -> [(label: String, value: String)]
    public var copyText: @MainActor (String) -> Void
    /// A colour row's colour as `#rrggbb`, whatever format its text is in; nil when it cannot be read.
    public var swatchHex: @MainActor (HistoryItem) -> String?

    public init(
        copy: @escaping @MainActor (HistoryItem) -> Void, reveal: @escaping @MainActor (HistoryItem) -> Void,
        edit: @escaping @MainActor (HistoryItem) -> Void, editLabel: @escaping @MainActor (HistoryItem) -> String?,
        colorFormats: @escaping @MainActor (HistoryItem) -> [(label: String, value: String)],
        copyText: @escaping @MainActor (String) -> Void,
        swatchHex: @escaping @MainActor (HistoryItem) -> String?
    ) {
        self.swatchHex = swatchHex
        self.copy = copy
        self.reveal = reveal
        self.edit = edit
        self.editLabel = editLabel
        self.colorFormats = colorFormats
        self.copyText = copyText
    }
}

enum GalleryMenu: Equatable {
    case date, pastedInto
}

/// View-only state: nothing the model's tests care about.
@MainActor
@Observable
final class GalleryUI {
    /// Bumped by ⌘F; the search field takes focus when it changes.
    var searchFocusRequests = 0
    /// The image preview is at 100% instead of fitted.
    var zoomed = false
    /// The preview fills the window, the column is hidden.
    var filled = false
    /// "Copied" on the button for a moment.
    var copied = false
    /// The filter dropdown that is open, if any.
    var openMenu: GalleryMenu?
}

/// The gallery: one window, the whole history on the left, a large preview on the right (10-gallery.md).
@MainActor
public final class GalleryWindowController: NSObject, NSWindowDelegate {
    public let model: GalleryModel
    let actions: GalleryActions
    let ui = GalleryUI()
    let thumbnails = ThumbnailCache(maximumSize: CGSize(width: 288, height: 192))
    let video = GalleryVideoPlayer()
    let gif = GalleryGIFPlayer()
    /// True when the window opens, false when it closes: the shell turns Deskpouch into a regular app meanwhile.
    public var onOpenChange: (@MainActor (Bool) -> Void)?

    private var window: GalleryWindow?
    private var copiedReset: Task<Void, Never>?

    static let minimumSize = CGSize(width: 900, height: 560)
    private static let frameName = "gallery"

    public init(store: HistoryStore, actions: GalleryActions) {
        model = GalleryModel(store: store)
        self.actions = actions
    }

    public var isOpen: Bool { window?.isVisible == true }

    /// Opens the window, or brings it forward. `selecting` puts that row in the preview.
    public func present(selecting id: UUID? = nil) {
        if window == nil {
            let window = makeWindow()
            self.window = window
            if !window.setFrameUsingName(Self.frameName) {
                let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
                let size = CGSize(width: min(1180, visible.width * 0.85), height: min(760, visible.height * 0.85))
                window.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: false)
            }
        }
        guard let window else { return }
        if !window.isVisible {
            model.reload()
            // Before the window shows: activating right after the policy flips is what brings the menu bar up.
            onOpenChange?(true)
        }
        if let id {
            model.show(id)
        } else if model.focused == nil {
            model.move(by: 1, extending: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
        // AppKit hands the keyboard to the first text field it finds, the search box: the list's keys (arrows, S,
        // F, Space) would then be typed into it. ⌘F is how the search gets focus.
        window.makeFirstResponder(nil)
    }

    /// A capture was logged or a row changed while the window is up.
    public func historyChanged() {
        guard isOpen else { return }
        model.refresh()
    }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        window?.saveFrame(usingName: Self.frameName)
        ui.filled = false
        ui.zoomed = false
        ui.openMenu = nil
        video.stop()
        gif.stop()
        model.cancelDelete()
        onOpenChange?(false)
    }

    // MARK: Actions

    /// A tile's mouse went up without a drag. A double-click fills the window with the preview.
    func tileClicked(_ item: HistoryItem, count: Int, flags: NSEvent.ModifierFlags) {
        ui.openMenu = nil
        ui.zoomed = false
        if count >= 2 {
            model.click(item.id, command: false, shift: false)
            ui.filled = true
        } else {
            model.click(item.id, command: flags.contains(.command), shift: flags.contains(.shift))
        }
    }

    /// A drag is leaving a tile: the whole selection when the tile is part of it, otherwise that tile alone
    /// (which becomes the selection, as in Finder).
    func dragPayloads(startingAt item: HistoryItem) -> [(writer: any NSPasteboardWriting, image: NSImage?)] {
        if !model.selectedIDs.contains(item.id) {
            model.click(item.id, command: false, shift: false)
        }
        return model.selectedItems.compactMap { row in
            guard let payload = GalleryExport.dragPayload(row, missing: model.missing) else { return nil }
            let picture = (row.thumbURL ?? row.fileURL).flatMap { thumbnails.image(for: $0) }
                .map { NSImage(cgImage: $0, size: CGSize(width: 72, height: 48)) }
            return (payload.writer, picture)
        }
    }

    /// ⌘C and the Copy button. One row goes through the app (an image is copied as an image, a transcript as
    /// text); several rows copy their files, or their texts when none has a file.
    func copyFocused() {
        let selected = model.selectedItems
        if selected.count > 1 {
            guard GalleryExport.copy(selected, missing: model.missing).write() else { return }
        } else {
            guard let item = model.focused else { return }
            actions.copy(item)
        }
        ui.copied = true
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.ui.copied = false
        }
    }

    func editFocused() {
        guard model.selectedIDs.count == 1, let item = model.focused, actions.editLabel(item) != nil else { return }
        actions.edit(item)
    }

    /// Escape, innermost first: the delete prompt, a filled or zoomed preview, a text field, then the window.
    func cancel() {
        if model.pendingDelete != nil {
            model.cancelDelete()
        } else if ui.openMenu != nil {
            ui.openMenu = nil
        } else if ui.filled {
            ui.filled = false
        } else if ui.zoomed {
            ui.zoomed = false
        } else if window?.firstResponder is NSTextView {
            window?.makeFirstResponder(nil)
        } else {
            close()
        }
    }

    /// Keys the window did not take as ⌘ shortcuts. `typing` is true while the search field has the keyboard;
    /// the arrows still move the list then.
    func handleKey(_ event: NSEvent, typing: Bool) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if model.pendingDelete != nil {
            // Return moves them to the Trash; every other key waits for an answer.
            if event.keyCode == 36 || event.keyCode == 76 { model.confirmDelete() }
            return true
        }
        switch event.keyCode {
        case 125 where flags.isSubset(of: .shift), 126 where flags.isSubset(of: .shift): // down, up
            ui.zoomed = false
            model.move(by: event.keyCode == 125 ? 1 : -1, extending: flags.contains(.shift))
            return true
        case 51 where flags == .command: // ⌘⌫
            guard !typing else { return false }
            model.requestDelete()
            return true
        default:
            break
        }
        guard !typing, flags.isEmpty else { return false }
        switch event.keyCode {
        case 49: // space: zoom a screenshot, play a recording, hold a GIF
            guard model.selectedIDs.count == 1, let item = model.focused else { return true }
            if item.kind == .screenshot {
                ui.zoomed.toggle()
            } else if item.fileURL?.pathExtension.lowercased() == "gif" {
                gif.toggle()
            } else if item.kind == .recording {
                video.toggle()
            }
            return true
        case 36, 76: // return
            editFocused()
            return true
        default:
            break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f":
            ui.filled.toggle()
            return true
        case "s":
            model.toggleStar()
            return true
        default:
            return false
        }
    }

    private func makeWindow() -> GalleryWindow {
        let window = GalleryWindow(
            contentRect: CGRect(origin: .zero, size: Self.minimumSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.controller = self
        window.title = "Gallery"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(hex: 0x121A_17)
        window.minSize = Self.minimumSize
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingView(rootView: GalleryView(controller: self))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        return window
    }

    #if DEBUG
    /// Space on the focused row, and where the player is afterwards. Verification only.
    public func debugPressSpace() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ) else { return }
        _ = handleKey(event, typing: false)
    }

    public var debugVideoState: String {
        "gif playing=\(gif.isPlaying) time=\(String(format: "%.2f", gif.time))/\(String(format: "%.2f", gif.duration)) · video playing=\(video.isPlaying) time=\(String(format: "%.2f", video.time)) duration=\(String(format: "%.2f", video.duration)) failed=\(video.failed)"
    }

    /// Opens the date dropdown, as a click on its chip does. Verification only.
    public func debugToggleDateMenu() { ui.openMenu = ui.openMenu == .date ? nil : .date }

    /// The window's frame on screen (AppKit global), for a demo that posts real clicks at it. Verification only.
    public var debugWindowFrame: CGRect? { window?.frame }

    /// Same as ⌘F. Verification only.
    public func debugFocusSearch() { ui.searchFocusRequests += 1 }

    /// For a ScreenCaptureKit snapshot of the window. Design review only.
    public var debugWindowNumber: Int? {
        window.flatMap { $0.isVisible ? $0.windowNumber : nil }
    }
    #endif
}

/// Routes the gallery's keys: ⌘ shortcuts, Escape, then the controller.
final class GalleryWindow: NSWindow {
    weak var controller: GalleryWindowController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private var isEditingText: Bool { firstResponder is NSTextView }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let controller else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w" where flags == .command:
            controller.close()
            return true
        case "f" where flags == .command:
            controller.ui.filled = false
            controller.ui.searchFocusRequests += 1
            return true
        case "c" where flags == .command && !isEditingText:
            controller.copyFocused()
            return true
        case "a" where flags == .command && !isEditingText:
            controller.model.selectAll()
            return true
        default:
            if controller.handleKey(event, typing: isEditingText) { return true }
            return super.performKeyEquivalent(with: event)
        }
    }

    /// The search field would swallow these: the arrows keep moving the list while typing, and the delete prompt
    /// takes every key whatever has focus.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, isEditingText, let controller,
           controller.model.pendingDelete != nil || event.keyCode == 125 || event.keyCode == 126,
           controller.handleKey(event, typing: true) {
            return
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event, typing: isEditingText) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }
}
