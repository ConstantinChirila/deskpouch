import AppKit
import DeskpouchCore
import Foundation
import Testing
@testable import DeskpouchGallery

@MainActor
struct GalleryExportTests {
    static func item(text: String? = nil, file: String? = nil, kind: HistoryKind? = nil) -> HistoryItem {
        HistoryItem(id: UUID(), toolID: "t", createdAt: Date(), text: text, fileURL: file.map { URL(fileURLWithPath: $0) },
                    duration: nil, pastedInto: nil, kind: kind)
    }

    @Test func copyingSeveralRowsTakesTheirFiles() {
        let shot = Self.item(file: "/tmp/a.png", kind: .screenshot)
        let clip = Self.item(file: "/tmp/b.mp4")
        let note = Self.item(text: "hello")
        #expect(GalleryExport.copy([shot, note, clip], missing: []) == .files([URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.mp4")]))
    }

    @Test func rowsWithoutFilesCopyAsTextJoinedByBlankLines() {
        let rows = [Self.item(text: "first"), Self.item(text: "#f59e0b", kind: .color), Self.item(text: "")]
        #expect(GalleryExport.copy(rows, missing: []) == .text("first\n\n#f59e0b"))
    }

    @Test func aMissingFileIsLeftOut() {
        let gone = Self.item(file: "/tmp/gone.png", kind: .screenshot)
        let note = Self.item(text: "hello")
        #expect(GalleryExport.copy([gone], missing: [gone.id]) == .nothing)
        // With the only file gone, the texts are what is left to copy.
        #expect(GalleryExport.copy([gone, note], missing: [gone.id]) == .text("hello"))
        #expect(GalleryExport.dragPayloads([gone, note], missing: [gone.id]) == [.text("hello")])
    }

    @Test func aDragCarriesOneItemPerRow() {
        let shot = Self.item(file: "/tmp/a.png", kind: .screenshot)
        let colour = Self.item(text: "#f59e0b", kind: .color)
        #expect(GalleryExport.dragPayloads([shot, colour], missing: []) == [.file(URL(fileURLWithPath: "/tmp/a.png")), .text("#f59e0b")])
    }

    @Test func writingPutsFilesOrTextOnThePasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("deskpouch-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(GalleryExport.files([URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.mp4")]).write(to: pasteboard))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls?.map(\.lastPathComponent) == ["a.png", "b.mp4"])
        #expect(GalleryExport.text("hello").write(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(!GalleryExport.nothing.write(to: pasteboard))
    }
}
