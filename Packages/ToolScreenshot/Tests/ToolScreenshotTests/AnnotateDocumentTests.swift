import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ToolScreenshot

@MainActor
struct AnnotateDocumentTests {
    func document(source: URL = URL(fileURLWithPath: "/tmp/Screenshot 2026-09-16 14.05.02.png")) -> AnnotateDocument {
        let context = CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        return AnnotateDocument(sourceURL: source, image: context.makeImage()!, pixelScale: 1, toolID: "screenshot")
    }

    @Test func dragCreatesOneMarkWithOneUndoStep() {
        let doc = document()
        doc.select(.box)
        doc.pointerDown(at: CGPoint(x: 10, y: 10), clickCount: 1)
        doc.pointerDragged(to: CGPoint(x: 50, y: 40), constrained: false)
        doc.pointerDragged(to: CGPoint(x: 90, y: 70), constrained: false)
        doc.pointerUp(at: CGPoint(x: 90, y: 70))
        #expect(doc.model.annotations.map(\.shape) == [.box(CGRect(x: 10, y: 10, width: 80, height: 60))])
        doc.undo()
        #expect(doc.model.annotations.isEmpty)
        #expect(!doc.model.canUndo)
    }

    @Test func clickWithADragToolLeavesNothing() {
        let doc = document()
        doc.select(.arrow)
        doc.pointerDown(at: CGPoint(x: 10, y: 10), clickCount: 1)
        doc.pointerUp(at: CGPoint(x: 10, y: 10))
        #expect(doc.model.annotations.isEmpty)
        #expect(!doc.model.canUndo)
    }

    @Test func clickingAMarkSelectsAndMovesIt() {
        let doc = document()
        doc.select(.blur)
        doc.pointerDown(at: CGPoint(x: 100, y: 100), clickCount: 1)
        doc.pointerDragged(to: CGPoint(x: 200, y: 200), constrained: false)
        doc.pointerUp(at: CGPoint(x: 200, y: 200))
        doc.model.selection = nil

        doc.pointerDown(at: CGPoint(x: 150, y: 150), clickCount: 1)
        #expect(doc.model.selection == doc.model.annotations[0].id)
        doc.pointerDragged(to: CGPoint(x: 160, y: 155), constrained: false)
        doc.pointerUp(at: CGPoint(x: 160, y: 155))
        #expect(doc.model.annotations[0].shape == .blur(CGRect(x: 110, y: 105, width: 100, height: 100)))
        doc.undo()
        #expect(doc.model.annotations[0].shape == .blur(CGRect(x: 100, y: 100, width: 100, height: 100)))
    }

    @Test func selectingAMarkWithoutMovingAddsNoStep() {
        let doc = document()
        doc.select(.blur)
        doc.pointerDown(at: CGPoint(x: 0, y: 0), clickCount: 1)
        doc.pointerDragged(to: CGPoint(x: 50, y: 50), constrained: false)
        doc.pointerUp(at: CGPoint(x: 50, y: 50))
        doc.pointerDown(at: CGPoint(x: 25, y: 25), clickCount: 1)
        doc.pointerUp(at: CGPoint(x: 25, y: 25))
        doc.undo()
        #expect(doc.model.annotations.isEmpty)
    }

    @Test func badgesStayWhenClickedAndCount() {
        let doc = document()
        doc.select(.badge)
        doc.pointerDown(at: CGPoint(x: 50, y: 50), clickCount: 1)
        doc.pointerUp(at: CGPoint(x: 50, y: 50))
        doc.pointerDown(at: CGPoint(x: 200, y: 50), clickCount: 1)
        doc.pointerUp(at: CGPoint(x: 200, y: 50))
        #expect(doc.model.annotations.map(\.shape) == [
            .badge(center: CGPoint(x: 50, y: 50), number: 1),
            .badge(center: CGPoint(x: 200, y: 50), number: 2),
        ])
    }

    @Test func textCommitsOnlyWhenNotEmpty() {
        let doc = document()
        doc.select(.text)
        doc.pointerDown(at: CGPoint(x: 50, y: 50), clickCount: 1)
        #expect(doc.draft != nil)
        #expect(doc.cancel())
        #expect(doc.model.annotations.isEmpty)

        doc.pointerDown(at: CGPoint(x: 50, y: 50), clickCount: 1)
        doc.draft?.string = "  Look here "
        doc.commitDraft()
        guard case .text(_, let string) = doc.model.annotations.first?.shape else {
            Issue.record("no text mark")
            return
        }
        #expect(string == "Look here")
    }

    @Test func doubleClickRetypesAndEmptyDeletes() throws {
        let doc = document()
        doc.select(.text)
        doc.pointerDown(at: CGPoint(x: 50, y: 50), clickCount: 1)
        doc.draft?.string = "Old"
        doc.commitDraft()
        let mark = try #require(doc.model.annotations.first)
        let inside = CGPoint(x: doc.metrics.bounds(of: mark).midX, y: doc.metrics.bounds(of: mark).midY)

        doc.pointerDown(at: inside, clickCount: 2)
        #expect(doc.draft?.id == mark.id)
        #expect(doc.visibleAnnotations.isEmpty)
        doc.draft?.string = ""
        doc.commitDraft()
        #expect(doc.model.annotations.isEmpty)
        doc.undo()
        #expect(doc.model.annotations.count == 1)
    }

    @Test func unsavedChangesFollowTheMarks() {
        let doc = document()
        #expect(doc.unsavedChanges == nil)
        #expect(doc.subtitle.hasSuffix("original saved"))
        doc.select(.badge)
        doc.pointerDown(at: CGPoint(x: 50, y: 50), clickCount: 1)
        doc.pointerUp(at: CGPoint(x: 50, y: 50))
        #expect(doc.unsavedChanges?.detail.contains("in /tmp") == true)
        #expect(doc.subtitle.hasSuffix("marks not exported"))
        doc.undo()
        #expect(doc.unsavedChanges == nil)

        doc.select(.text)
        doc.pointerDown(at: CGPoint(x: 50, y: 50), clickCount: 1)
        #expect(doc.unsavedChanges == nil)
        doc.draft?.string = "Hi"
        #expect(doc.unsavedChanges != nil)
    }

    @Test func documentKeyIsTheFile() {
        let a = document(source: URL(fileURLWithPath: "/tmp/x/../a.png"))
        let b = document(source: URL(fileURLWithPath: "/tmp/a.png"))
        let c = document(source: URL(fileURLWithPath: "/tmp/c.png"))
        #expect(a.documentKey == b.documentKey)
        #expect(a.documentKey != c.documentKey)
    }

    @Test func colourChangeAppliesToTheSelection() {
        let doc = document()
        doc.select(.box)
        doc.pointerDown(at: CGPoint(x: 10, y: 10), clickCount: 1)
        doc.pointerDragged(to: CGPoint(x: 90, y: 90), constrained: false)
        doc.pointerUp(at: CGPoint(x: 90, y: 90))
        doc.setColor(.white)
        #expect(doc.model.annotations[0].color == .white)
    }

    @Test func shiftSnapsArrowsAndSquares() {
        let arrow = AnnotateDocument.constrain(CGPoint(x: 100, y: 8), from: .zero, tool: .arrow)
        #expect(abs(arrow.y) < 0.001)
        let square = AnnotateDocument.constrain(CGPoint(x: -30, y: 10), from: .zero, tool: .box)
        #expect(square == CGPoint(x: -30, y: 30))
    }

    @Test func exportNameSitsBesideTheSourceWithoutStacking() {
        let folder = URL(fileURLWithPath: "/Users/x/Pictures/Deskpouch")
        #expect(AnnotateDocument.exportURL(for: folder.appending(path: "Screenshot 2026-09-16 14.05.02.png")).lastPathComponent
                == "Screenshot 2026-09-16 14.05.02 annotated.png")
        #expect(AnnotateDocument.exportURL(for: folder.appending(path: "Screenshot 2026-09-16 14.05.02 annotated.png")).lastPathComponent
                == "Screenshot 2026-09-16 14.05.02 annotated.png")
        #expect(AnnotateDocument.exportURL(for: folder.appending(path: "Screenshot 2026-09-16 14.05.02 annotated 3.png")).lastPathComponent
                == "Screenshot 2026-09-16 14.05.02 annotated.png")
        #expect(AnnotateDocument.exportURL(for: folder.appending(path: "a.png")).deletingLastPathComponent().path == folder.path)
    }

    @Test func exportWritesANewFileAndKeepsTheOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Screenshot 2026-09-16 14.05.02.png")
        try Data("original".utf8).write(to: source)

        let doc = document(source: source)
        doc.model.add(Annotation(shape: .box(CGRect(x: 10, y: 10, width: 50, height: 50))))
        let first = try #require(try await doc.export())
        let second = try #require(try await doc.export())
        #expect(first.fileURL?.lastPathComponent == "Screenshot 2026-09-16 14.05.02 annotated.png")
        #expect(second.fileURL?.lastPathComponent == "Screenshot 2026-09-16 14.05.02 annotated 2.png")
        #expect(first.kind == .screenshot)
        #expect(first.followUp == nil)
        #expect(try Data(contentsOf: source) == Data("original".utf8))
        let written = try #require(first.fileURL.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) })
        #expect(CGImageSourceCreateImageAtIndex(written, 0, nil)?.width == 400)
    }
}
