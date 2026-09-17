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
        editor.load(StubDocument(), toolID: "stub")
        editor.requestClose()
        #expect(!editor.confirmingDiscard)
    }

    @Test func closeWithChangesAsksAndKeepEditingDismisses() {
        let (editor, _) = controller()
        let doc = StubDocument()
        doc.unsavedChanges = Self.changes
        editor.load(doc, toolID: "stub")
        editor.requestClose()
        #expect(editor.confirmingDiscard)
        editor.cancel()
        #expect(!editor.confirmingDiscard)
        editor.requestClose()
        editor.discard()
        #expect(!editor.confirmingDiscard)
    }

    @Test func promptSwallowsOtherKeys() throws {
        let (editor, _) = controller()
        let doc = StubDocument()
        doc.unsavedChanges = Self.changes
        editor.load(doc, toolID: "stub")
        editor.requestClose()
        let key = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7
        ))
        #expect(editor.handleKey(key))
        #expect(editor.confirmingDiscard)
    }

    @Test func exportDeliversOnce() async {
        let (editor, delivered) = controller()
        let doc = StubDocument()
        editor.load(doc, toolID: "stub")
        editor.performExport()
        editor.performExport()
        #expect(editor.exporting)
        doc.finishExport()
        await editor.exportTask?.value
        #expect(delivered().count == 1)
        #expect(!editor.exporting)
    }

    @Test func closeRequestsWaitForAnExport() async {
        let (editor, delivered) = controller()
        let doc = StubDocument()
        doc.unsavedChanges = Self.changes
        editor.load(doc, toolID: "stub")
        editor.performExport()
        editor.requestClose()
        #expect(!editor.confirmingDiscard)
        doc.finishExport()
        await editor.exportTask?.value
        #expect(delivered().count == 1)
    }

    @Test func exportStillDeliversWhenAnotherDocumentReplacedIt() async {
        let (editor, delivered) = controller()
        let first = StubDocument()
        editor.load(first, toolID: "stub")
        editor.performExport()
        let task = editor.exportTask
        editor.load(StubDocument(), toolID: "stub")
        #expect(first.closed == 1)
        #expect(!editor.exporting)
        first.finishExport()
        await task?.value
        #expect(delivered().count == 1)
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
