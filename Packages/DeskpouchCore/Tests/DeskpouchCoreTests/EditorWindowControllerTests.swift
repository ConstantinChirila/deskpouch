import AppKit
import SwiftUI
import Testing
@testable import DeskpouchCore

/// A document whose unsaved state and export are set by the test. `export` waits until `finishExport` is called.
@MainActor
final class StubDocument: EditorDocument {
    var title = "Stub"
    var subtitle = ""
    var idealContentSize = CGSize(width: 100, height: 100)
    var unsavedChanges: UnsavedChanges?
    var documentKey: String?
    var exportResult: ToolResult? = ToolResult(toolID: "stub", text: "done")
    private(set) var closed = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false

    func makeContent() -> AnyView { AnyView(EmptyView()) }
    func makeToolbar() -> AnyView { AnyView(EmptyView()) }
    func copy() {}
    func close() { closed += 1 }

    func export() async throws -> ToolResult? {
        if !released {
            await withCheckedContinuation { gate = $0 }
        }
        return exportResult
    }

    func finishExport() {
        released = true
        gate?.resume()
        gate = nil
    }
}

@MainActor
struct EditorWindowControllerTests {
    static let changes = UnsavedChanges(title: "Discard?", detail: "Marks are not saved.")

    func controller() -> (EditorWindowController, () -> [ToolResult]) {
        let controller = EditorWindowController()
        var delivered: [ToolResult] = []
        controller.deliver = { delivered.append($0) }
        return (controller, { delivered })
    }

    @Test func closeWithoutChangesDoesNotAsk() {
        let (editor, _) = controller()
        let session = editor.open(StubDocument(), toolID: "stub")
        session.requestClose()
        #expect(!session.confirmingDiscard)
        #expect(!editor.isOpen)
    }

    @Test func closeWithChangesAsksAndKeepEditingDismisses() {
        let (editor, _) = controller()
        let doc = StubDocument()
        doc.unsavedChanges = Self.changes
        let session = editor.open(doc, toolID: "stub")
        session.requestClose()
        #expect(session.confirmingDiscard)
        session.cancel()
        #expect(!session.confirmingDiscard)
        #expect(editor.isOpen)
        session.requestClose()
        session.discard()
        #expect(!editor.isOpen)
        #expect(doc.closed == 1)
    }

    @Test func promptSwallowsOtherKeys() throws {
        let (editor, _) = controller()
        let doc = StubDocument()
        doc.unsavedChanges = Self.changes
        let session = editor.open(doc, toolID: "stub")
        session.requestClose()
        let key = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7
        ))
        #expect(session.handleKey(key))
        #expect(session.confirmingDiscard)
    }

    @Test func exportDeliversOnceAndCloses() async {
        let (editor, delivered) = controller()
        let doc = StubDocument()
        let session = editor.open(doc, toolID: "stub")
        session.performExport()
        session.performExport()
        #expect(session.exporting)
        doc.finishExport()
        await session.exportTask?.value
        #expect(delivered().count == 1)
        #expect(!session.exporting)
        #expect(!editor.isOpen)
    }

    @Test func closeRequestsWaitForAnExport() async {
        let (editor, delivered) = controller()
        let doc = StubDocument()
        doc.unsavedChanges = Self.changes
        let session = editor.open(doc, toolID: "stub")
        session.performExport()
        session.requestClose()
        session.discard()
        #expect(!session.confirmingDiscard)
        #expect(editor.isOpen)
        doc.finishExport()
        await session.exportTask?.value
        #expect(delivered().count == 1)
    }

    @Test func documentsOpenSideBySide() {
        let (editor, _) = controller()
        let first = StubDocument()
        first.unsavedChanges = Self.changes
        let second = StubDocument()
        editor.open(first, toolID: "stub")
        let secondSession = editor.open(second, toolID: "stub")
        #expect(editor.documents.count == 2)
        #expect(first.closed == 0)
        secondSession.requestClose()
        #expect(editor.documents.count == 1)
        #expect(editor.documents.first === first)
    }

    @Test func sameKeyFindsTheOpenWindow() {
        let (editor, _) = controller()
        let open = StubDocument()
        open.documentKey = "/a.png"
        let session = editor.open(open, toolID: "stub")
        let again = StubDocument()
        again.documentKey = "/a.png"
        let other = StubDocument()
        other.documentKey = "/b.png"
        #expect(editor.session(showing: again) === session)
        #expect(editor.session(showing: other) == nil)
        #expect(editor.session(showing: StubDocument()) == nil)
    }

    @Test func closeWhereClosesMatchingDocumentsOnly() {
        let (editor, _) = controller()
        let keep = StubDocument()
        keep.title = "Keep"
        let drop = StubDocument()
        drop.title = "Drop"
        drop.unsavedChanges = Self.changes
        editor.open(keep, toolID: "stub")
        editor.open(drop, toolID: "stub")
        editor.close { $0.title == "Drop" }
        #expect(editor.documents.map(\.title) == ["Keep"])
        #expect(drop.closed == 1)
    }

    /// The window's root view holds the session: closing has to break that, or both stay in memory.
    @Test func closedSessionAndWindowAreReleased() async {
        let (editor, _) = controller()
        weak var session: EditorSession?
        weak var window: NSWindow?
        do {
            let opened = editor.open(StubDocument(), toolID: "stub")
            opened.prepareWindow()
            session = opened
            window = opened.window
            #expect(window != nil)
            opened.close()
        }
        // The content view is dropped a turn after the close.
        for _ in 0..<10 where session != nil || window != nil { await Task.yield() }
        #expect(session == nil)
        #expect(window == nil)
    }

    @Test func fittedFrameClampsAndCentres() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let small = EditorWindowController.fittedFrame(for: CGSize(width: 100, height: 100), in: visible)
        #expect(small.size == EditorWindowController.minimumSize)
        #expect(small.midX == 500 && small.midY == 400)

        let huge = EditorWindowController.fittedFrame(for: CGSize(width: 4000, height: 1000), in: visible)
        #expect(huge.width <= 850)
        #expect(huge.height >= EditorWindowController.minimumSize.height)
    }
}

@MainActor
struct CapturedPillTests {
    func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    @Test func followUpRunsOnceAndHides() {
        let overlay = OverlayController()
        var runs = 0
        overlay.showCaptured(thumbnail: nil, title: "Saved", hint: "a.png", action: "Annotate") { runs += 1 }
        #expect(overlay.state.isCaptured)
        overlay.followUpRequested()
        overlay.followUpRequested()
        #expect(runs == 1)
        #expect(overlay.state == .hidden)
    }

    @Test func anotherStateDropsTheHandlerAndThumbnail() {
        let overlay = OverlayController()
        var runs = 0
        overlay.showCaptured(thumbnail: image(width: 40, height: 20), title: "Saved", hint: "a.png", action: "Annotate") { runs += 1 }
        #expect(overlay.thumbnail != nil)
        overlay.show(.copied)
        #expect(overlay.thumbnail == nil)
        overlay.followUpRequested()
        #expect(runs == 0)
    }

    @Test func thumbnailIsSmall() throws {
        let small = try #require(OverlayController.pillThumbnail(image(width: 5120, height: 2880)))
        #expect(small.width == 160 && small.height == 90)
    }
}
