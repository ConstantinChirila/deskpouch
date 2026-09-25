import AppKit
import Observation
import SwiftUI
import os

private let editorLog = Logger(subsystem: "com.constantinchirila.deskpouch", category: "editor")

/// What a tool shows in an editor window: Annotate (01), Diff (04), Trim (05).
@MainActor
public protocol EditorDocument: AnyObject {
    var title: String { get }
    /// Second header line, e.g. the file name.
    var subtitle: String { get }
    /// Content size the document would like at 1:1, in points. The window fits it to the screen.
    var idealContentSize: CGSize { get }
    /// Two documents with the same key are the same thing (e.g. one file): opening the second brings the first
    /// one's window forward instead. Nil means always open a new window.
    var documentKey: String? { get }
    /// The main area. Built once per window.
    func makeContent() -> AnyView
    /// Controls on the left of the bottom bar.
    func makeToolbar() -> AnyView
    /// ⌘C and the Copy button: put the current result on the pasteboard.
    func copy()
    /// ⌘S and the Export button. The returned result goes through the output pipeline like any capture; nil
    /// means nothing to deliver.
    func export() async throws -> ToolResult?
    /// A key the window did not handle itself. Return true when used.
    func handleKey(_ event: NSEvent) -> Bool
    /// Escape. Return true when the document used it (ending an edit, clearing a selection); false closes.
    func cancel() -> Bool
    /// The window is closing.
    func close()
    /// Non-nil while closing would lose work: the prompt's title and explanation.
    var unsavedChanges: UnsavedChanges? { get }
}

/// What the discard prompt says.
public struct UnsavedChanges: Equatable, Sendable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public extension EditorDocument {
    var documentKey: String? { nil }
    func handleKey(_ event: NSEvent) -> Bool { false }
    func cancel() -> Bool { false }
    func close() {}
    var unsavedChanges: UnsavedChanges? { nil }
}

/// Editor windows for every tool (00-foundation.md, step 3). One window per document, so several screenshots
/// can be open at once (changed 2026-09-17 from "one editor, a second replaces the first"). Custom chrome on the
/// panel gradient: header with title and close, the document's content, bottom bar with the document's controls
/// left and Copy / Export right. Escape and ⌘W close (asking first with unsaved work), ⌘C copies, ⌘S exports.
@MainActor
public final class EditorWindowController {
    /// Where exported results go; the shell feeds them to the output pipeline.
    public var deliver: (@MainActor (ToolResult) -> Void)?
    /// True when the first editor opens, false when the last one closes. The shell turns Deskpouch into a regular
    /// app (Dock icon, ⌘Tab) for as long as a real window is up.
    public var onOpenChange: (@MainActor (Bool) -> Void)?

    /// Open windows, oldest first.
    private(set) var sessions: [EditorSession] = []
    /// The app in front before the first editor opened; it gets focus back when the last one closes.
    private var previousApp: NSRunningApplication?

    static let minimumSize = CGSize(width: 720, height: 480)
    /// Header, bottom bar, gaps and padding around the content.
    static let chrome = CGSize(width: 36, height: 36 + 14 + 14 + 34 + 32)

    public init() {}

    public var isOpen: Bool { !sessions.isEmpty }

    /// Documents in open windows, oldest first.
    public var documents: [any EditorDocument] { sessions.compactMap(\.document) }

    /// Opens `document` in a new window, or brings forward the window already showing the same thing.
    public func present(_ document: any EditorDocument, for toolID: String) {
        if let existing = session(showing: document) {
            document.close()
            existing.show()
            editorLog.info("present \(toolID, privacy: .public): already open, focusing")
            return
        }
        if sessions.isEmpty {
            let frontmost = NSWorkspace.shared.frontmostApplication
            previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
            // Before the window shows: `show` activates the app, which is what brings the menu bar up.
            onOpenChange?(true)
        }
        let previous = sessions.last?.window
        let session = open(document, toolID: toolID)
        session.show(after: previous)
        editorLog.info("present \(toolID, privacy: .public) \(document.title, privacy: .public), \(self.sessions.count) open")
    }

    /// The open window for the same thing as `document` (same `documentKey`), if any.
    func session(showing document: any EditorDocument) -> EditorSession? {
        guard let key = document.documentKey else { return nil }
        return sessions.first { $0.document?.documentKey == key }
    }

    /// Adds a session without showing a window. The model half of `present`, split out for tests.
    @discardableResult
    func open(_ document: any EditorDocument, toolID: String) -> EditorSession {
        let session = EditorSession(document: document, toolID: toolID, owner: self)
        sessions.append(session)
        return session
    }

    /// Quit: false when an editor has unsaved work. That editor comes forward with its discard prompt up, and the
    /// quit is called off until the user has answered.
    public func readyToQuit() -> Bool {
        guard let unsaved = sessions.first(where: { $0.document?.unsavedChanges != nil && !$0.exporting }) else { return true }
        unsaved.show()
        unsaved.requestClose()
        return false
    }

    public var isExporting: Bool { sessions.contains(where: \.exporting) }

    /// Quit: returns once every export in flight has written its file and handed it to `deliver`.
    public func finishExports() async {
        for task in sessions.compactMap(\.exportTask) { await task.value }
    }

    /// Closes, without asking, every window whose document matches (e.g. a tool being switched off).
    public func close(where matches: (any EditorDocument) -> Bool) {
        for session in sessions where session.document.map(matches) == true {
            session.close()
        }
    }

    func sessionClosed(_ session: EditorSession) {
        sessions.removeAll { $0 === session }
        guard sessions.isEmpty else { return }
        onOpenChange?(false)
        // Hand focus back to whatever was in front before the editors, so ⌘V lands there.
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    /// The document's size plus chrome, no larger than 85% of `visible`, no smaller than the minimum, centred.
    static func fittedFrame(for ideal: CGSize, in visible: CGRect) -> CGRect {
        let maxSize = CGSize(width: visible.width * 0.85, height: visible.height * 0.85)
        var size = CGSize(width: ideal.width + Self.chrome.width, height: ideal.height + Self.chrome.height)
        if size.width > maxSize.width || size.height > maxSize.height {
            let scale = min(maxSize.width / size.width, maxSize.height / size.height)
            size = CGSize(width: size.width * scale, height: size.height * scale)
        }
        size.width = max(Self.minimumSize.width, size.width.rounded())
        size.height = max(Self.minimumSize.height, size.height.rounded())
        return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    #if DEBUG
    // Verification hooks; they act on the newest window.

    /// For a ScreenCaptureKit snapshot of the newest window. Design review only.
    public var debugWindowNumber: Int? {
        sessions.last?.window.flatMap { $0.isVisible ? $0.windowNumber : nil }
    }

    /// Same path as Escape with nothing else to dismiss, then the prompt's Keep editing.
    public func debugRequestClose() { sessions.last?.requestClose() }
    public func debugKeepEditing() { sessions.last?.keepEditing() }
    public var debugConfirmingDiscard: Bool { sessions.last?.confirmingDiscard ?? false }

    /// Same path as the Export button.
    public func debugExport() {
        sessions.last?.performExport()
    }
    #endif
}

/// One editor window and its document.
@MainActor
@Observable
final class EditorSession: NSObject {
    /// Cleared on close, which releases the document's image.
    private(set) var document: (any EditorDocument)?
    let toolID: String
    private(set) var content: AnyView?
    private(set) var toolbar: AnyView?
    private(set) var exporting = false
    private(set) var copied = false
    private(set) var failure: String?
    /// The discard prompt is up.
    private(set) var confirmingDiscard = false

    @ObservationIgnored private(set) var window: EditorWindow?
    @ObservationIgnored private weak var owner: EditorWindowController?
    @ObservationIgnored private var copiedReset: Task<Void, Never>?
    @ObservationIgnored private var closed = false
    /// The running export, for tests.
    @ObservationIgnored private(set) var exportTask: Task<Void, Never>?

    init(document: any EditorDocument, toolID: String, owner: EditorWindowController) {
        self.document = document
        self.toolID = toolID
        self.owner = owner
        content = document.makeContent()
        toolbar = document.makeToolbar()
        super.init()
    }

    /// Shows the window (creating it the first time), cascaded from `previous` when another editor is open.
    func show(after previous: NSWindow? = nil) {
        prepareWindow(after: previous)
        guard let window else { return }
        // Opened from the pill (a non-activating panel) Deskpouch is not the active app, and `NSApp.activate()`
        // is refused under cooperative activation: the window opened behind the frontmost app. The older call
        // still forces it, and `orderFrontRegardless` keeps the window on top even if activation fails.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// Creates and places the window without showing it. Does nothing once there is one, or after close. Split
    /// out of `show` for tests.
    func prepareWindow(after previous: NSWindow? = nil) {
        guard window == nil, !closed else { return }
        let window = makeWindow()
        self.window = window
        if let previous {
            // Same size as the newest editor, shifted down-right so both title rows stay visible.
            window.setFrame(previous.frame.offsetBy(dx: 28, dy: -28), display: false)
        } else if !window.setFrameUsingName(Self.frameName(toolID)), let document {
            window.setFrame(EditorWindowController.fittedFrame(for: document.idealContentSize, in: targetScreen().visibleFrame), display: false)
        }
    }

    /// Close button, ⌘W and Escape: asks first when the document has unsaved work. Ignored while exporting:
    /// the export closes the window itself.
    func requestClose() {
        guard !exporting else { return }
        if document?.unsavedChanges != nil {
            // Take the keyboard from a text field being typed in, so the prompt's keys reach `handleKey`.
            window?.makeFirstResponder(nil)
            confirmingDiscard = true
        } else {
            close()
        }
    }

    func keepEditing() {
        confirmingDiscard = false
    }

    func discard() {
        guard !exporting else { return }
        confirmingDiscard = false
        close()
    }

    /// Closes without asking.
    func close() {
        // `close()`, not `performClose`: the standard close button is hidden. `windowWillClose` does the cleanup.
        if let window, window.isVisible {
            window.close()
        } else {
            finish()
        }
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        if let window { window.saveFrame(usingName: Self.frameName(toolID)) }
        document?.close()
        document = nil
        confirmingDiscard = false
        content = nil
        toolbar = nil
        copiedReset?.cancel()
        owner?.sessionClosed(self)
        // The window's hosting view holds this session through its root view, and the session holds the window:
        // let go of both, or every closed editor stays in memory. The view goes on the next turn because this
        // can run inside `windowWillClose`, while AppKit is still using the window.
        if let window {
            self.window = nil
            Task { @MainActor in window.contentView = nil }
        }
    }

    // MARK: Actions

    func performCopy() {
        guard let document else { return }
        document.copy()
        copied = true
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }

    func performExport() {
        guard let document, !exporting else { return }
        confirmingDiscard = false
        exporting = true
        failure = nil
        let deliver = owner?.deliver
        exportTask = Task { [weak self] in
            do {
                let result = try await document.export()
                // The file is written by now: deliver it even if the window went away meanwhile, or it would
                // sit in the folder without being copied or logged.
                if let result { deliver?(result) }
                guard let self else { return }
                exporting = false
                close()
            } catch {
                editorLog.error("export failed: \(String(describing: error), privacy: .public)")
                guard let self else { return }
                exporting = false
                failure = "Export failed"
            }
        }
    }

    /// Escape: dismisses the prompt, then lets the document use it, then asks to close.
    func cancel() {
        if confirmingDiscard {
            keepEditing()
            return
        }
        if document?.cancel() == true { return }
        requestClose()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        if confirmingDiscard {
            // Return exports, D discards; every other key waits for a choice.
            if event.keyCode == 36 || event.keyCode == 76 {
                performExport()
            } else if event.charactersIgnoringModifiers?.lowercased() == "d", event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                discard()
            }
            return true
        }
        return document?.handleKey(event) ?? false
    }

    // MARK: Window

    private func makeWindow() -> EditorWindow {
        let window = EditorWindow(
            contentRect: CGRect(origin: .zero, size: EditorWindowController.minimumSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.controller = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(hex: 0x121A_17)
        window.minSize = EditorWindowController.minimumSize
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingView(rootView: EditorChrome(controller: self))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        return window
    }

    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func frameName(_ toolID: String) -> String {
        "editor.\(toolID)"
    }
}

extension EditorSession: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        finish()
    }
}

/// Routes the editor's keys: ⌘ shortcuts, Escape, then the document.
final class EditorWindow: NSWindow {
    weak var controller: EditorSession?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// A text field has the keyboard: copy, undo and friends belong to it.
    private var isEditingText: Bool {
        firstResponder is NSTextView
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let controller else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w" where flags == .command:
            controller.requestClose()
            return true
        case "s" where flags == .command:
            controller.performExport()
            return true
        case "c" where flags == .command && !isEditingText:
            controller.performCopy()
            return true
        default:
            if controller.confirmingDiscard || !isEditingText, controller.handleKey(event) { return true }
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        // The discard prompt takes every key, whatever has focus.
        if controller?.confirmingDiscard == true || !isEditingText, controller?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }
}

/// Header, content, bottom bar.
struct EditorChrome: View {
    let controller: EditorSession

    var body: some View {
        VStack(spacing: 14) {
            header
            if let content = controller.content {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(!controller.confirmingDiscard)
                    .overlay {
                        if controller.confirmingDiscard, let changes = controller.document?.unsavedChanges {
                            DiscardPrompt(changes: changes, controller: controller)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: controller.confirmingDiscard)
            } else {
                Spacer()
            }
            bottomBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panelGradient)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .foregroundStyle(Theme.Colors.text)
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            PouchMark()
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.document?.title ?? "")
                    .font(.dp(15, .semibold))
                    .tracking(-0.15)
                Text(controller.document?.subtitle ?? "")
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button { controller.requestClose() } label: {
                CloseIcon()
                    .stroke(style: .icon(1.6))
                    .foregroundStyle(Theme.Colors.text.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).fill(Theme.Colors.tint(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).strokeBorder(Theme.Colors.tint(0.12), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
        }
        .frame(height: 36)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if let toolbar = controller.toolbar { toolbar }
            Spacer(minLength: 16)
            if let failure = controller.failure {
                Text(failure)
                    .font(.dp(12))
                    .foregroundStyle(Theme.Colors.record)
            }
            EditorButton(
                title: controller.copied ? "Copied" : "Copy", hint: "⌘C", primary: false,
                icon: controller.copied ? AnyShape(CheckIcon()) : AnyShape(CopyIcon())
            ) { controller.performCopy() }
            EditorButton(
                title: controller.exporting ? "Exporting" : "Export", hint: "⌘S", primary: true,
                icon: AnyShape(CheckIcon())
            ) { controller.performExport() }
            .disabled(controller.exporting)
        }
        .frame(height: 34)
    }
}

/// Asked before closing with unsaved work. Sits over the dimmed content, in the panel's card style.
private struct DiscardPrompt: View {
    let changes: UnsavedChanges
    let controller: EditorSession

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .onTapGesture { controller.keepEditing() }
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Theme.Colors.record)
                        .frame(width: 10, height: 10)
                        .shadow(color: Theme.Colors.record(0.9), radius: 6)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(changes.title)
                            .font(.dp(15, .semibold))
                        Text(changes.detail)
                            .font(.dp(13))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    PromptButton(title: "Discard", hint: "D", style: .destructive) { controller.discard() }
                    Spacer(minLength: 8)
                    PromptButton(title: "Keep editing", hint: "Esc", style: .plain) { controller.keepEditing() }
                    PromptButton(title: "Export", hint: "↩", style: .primary) { controller.performExport() }
                }
            }
            .padding(20)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.panelGradient))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.Colors.record(0.30), lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.Colors.record(0.07), lineWidth: 6).padding(-3))
            .shadow(color: .black.opacity(0.6), radius: 25, y: 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

private struct PromptButton: View {
    enum Style { case primary, plain, destructive }

    let title: String
    let hint: String
    let style: Style
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.dp(13, .semibold))
                Text(hint).font(.dp(11)).opacity(0.6)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch style {
        case .primary: Theme.Colors.accentInk
        case .plain: Theme.Colors.text
        case .destructive: Theme.Colors.record
        }
    }

    private var fill: Color {
        switch style {
        case .primary: Theme.Colors.accent
        case .plain: Theme.Colors.tint(0.07)
        case .destructive: Theme.Colors.record(0.10)
        }
    }

    private var border: Color {
        switch style {
        case .primary: Color.white.opacity(0.18)
        case .plain: Theme.Colors.tint(0.14)
        case .destructive: Theme.Colors.record(0.35)
        }
    }
}

/// The brand pouch at tile size, marking the window as Deskpouch's.
private struct PouchMark: View {
    var body: some View {
        PouchIcon()
            .stroke(style: .icon(1.6))
            .foregroundStyle(Theme.Colors.accentHigh)
            .frame(width: 16, height: 16)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).fill(Theme.Colors.accent(0.14)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.Colors.accent(0.25), lineWidth: 1))
    }
}

/// Bottom-bar button. Primary: amber capsule, ink text. Secondary: tint capsule.
struct EditorButton: View {
    let title: String
    let hint: String
    let primary: Bool
    let icon: AnyShape
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                    .stroke(style: .icon(primary ? 2.2 : 1.6))
                    .frame(width: 12, height: 12)
                Text(title)
                    .font(.dp(13, .semibold))
                Text(hint)
                    .font(.dp(11))
                    .opacity(0.6)
            }
            .foregroundStyle(primary ? Theme.Colors.accentInk : Theme.Colors.text)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(primary ? AnyShapeStyle(Theme.Colors.accent) : AnyShapeStyle(Theme.Colors.tint(0.07))))
            .overlay(Capsule().strokeBorder(primary ? Color.white.opacity(0.18) : Theme.Colors.tint(0.14), lineWidth: 1))
            .shadow(color: primary ? Theme.Colors.accent(0.35) : .clear, radius: 8, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
