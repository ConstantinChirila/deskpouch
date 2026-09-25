import AVFoundation
import Foundation
import Testing
@testable import ToolScreenRecorder

@MainActor
struct TrimDocumentTests {
    @Test func pressLandsOnAHandleOrThePlayhead() {
        // Kept part from x 100 to 300, handles 12 wide outside it.
        func target(_ x: CGFloat) -> TrimDragTarget { .at(x: x, startX: 100, endX: 300, handleWidth: 12) }
        #expect(target(92) == .start)
        #expect(target(104) == .start)
        #expect(target(306) == .end)
        #expect(target(296) == .end)
        #expect(target(200) == .playhead)
        #expect(target(40) == .playhead)
    }

    @Test func aTinyKeptPartGivesThePressToTheNearerHandle() {
        #expect(TrimDragTarget.at(x: 101, startX: 100, endX: 106, handleWidth: 12) == .start)
        #expect(TrimDragTarget.at(x: 105, startX: 100, endX: 106, handleWidth: 12) == .end)
    }

    @Test func exportNames() {
        let source = URL(fileURLWithPath: "/tmp/Recording 2026-09-19 14.05.02.mp4")
        #expect(TrimDocument.exportURL(for: source, format: .mp4, trimmed: true).lastPathComponent == "Recording 2026-09-19 14.05.02 trimmed.mp4")
        #expect(TrimDocument.exportURL(for: source, format: .gif, trimmed: true).lastPathComponent == "Recording 2026-09-19 14.05.02 trimmed.gif")
        // The whole recording as a GIF is not a trim.
        #expect(TrimDocument.exportURL(for: source, format: .gif, trimmed: false).lastPathComponent == "Recording 2026-09-19 14.05.02.gif")
        // Trimming a trimmed file does not stack the suffix.
        let again = URL(fileURLWithPath: "/tmp/Recording 2026-09-19 14.05.02 trimmed 2.mp4")
        #expect(TrimDocument.exportURL(for: again, format: .mp4, trimmed: true).lastPathComponent == "Recording 2026-09-19 14.05.02 trimmed.mp4")
    }

    @Test func filmstripTileCountFollowsTheShape() {
        #expect(TrimDocument.thumbnailCount(aspect: 16.0 / 9) == 11)
        #expect(TrimDocument.thumbnailCount(aspect: 0.1) == 30)
        #expect(TrimDocument.thumbnailCount(aspect: 5) == 6)
    }

    @Test func sweepDeletesOnlyOldCopies() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "trimcopies-\(UUID().uuidString)")
        let old = folder.appending(path: "old"), fresh = folder.appending(path: "fresh")
        for copy in [old, fresh] {
            try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
            try Data([1]).write(to: copy.appending(path: "Recording trimmed.gif"))
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-TrimDocument.copyLifetime - 60)], ofItemAtPath: old.path)

        TrimDocument.sweepCopies(in: folder, now: now)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        // A folder that is not there is nothing to sweep.
        TrimDocument.sweepCopies(in: folder.appending(path: "missing"), now: now)
    }

    @Test func aGIFOverTheCapIsRefusedAndAnMP4IsNot() async throws {
        let source = try await TrimExportTests.makeVideo(seconds: TrimDocument.gifMaxLength + 1, size: CGSize(width: 64, height: 36))
        let folder = source.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: source) }
        let document = TrimDocument(sourceURL: source, media: try await TrimDocument.Media.load(source), toolID: "screen")
        defer { document.close() }

        #expect(!document.gifIsTooLong)
        document.format = .gif
        #expect(document.gifIsTooLong)
        await #expect(throws: TrimExportError.self) { try await document.export() }
        let name = TrimDocument.exportURL(for: source, format: .gif, trimmed: false).lastPathComponent
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: name).path))

        document.dragEnd(to: 1)
        #expect(!document.gifIsTooLong)
    }

    @Test func exportWritesTheKeptPartBesideTheSourceAndKeepsIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "trimdoc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try await TrimExportTests.makeVideo(seconds: 2, size: CGSize(width: 320, height: 180))
        let source = folder.appending(path: "Recording 2026-09-19 14.05.02.mp4")
        try FileManager.default.moveItem(at: made, to: source)

        let media = try await TrimDocument.Media.load(source)
        #expect(abs(media.duration - 2) < 0.05)
        #expect(media.pixelSize == CGSize(width: 320, height: 180))
        let document = TrimDocument(sourceURL: source, media: media, toolID: "screen")
        defer { document.close() }
        #expect(document.unsavedChanges == nil)
        document.dragStart(to: 0.5)
        document.dragEnd(to: 1.5)
        #expect(document.unsavedChanges != nil)

        let result = try #require(try await document.export())
        let file = try #require(result.fileURL)
        #expect(file.lastPathComponent == "Recording 2026-09-19 14.05.02 trimmed.mp4")
        #expect(file.deletingLastPathComponent().path == folder.path)
        #expect(result.kind == .recording)
        #expect(abs((result.duration ?? 0) - 1) < 1e-9)
        #expect(abs(try await AVURLAsset(url: file).load(.duration).seconds - 1) < 0.1)
        #expect(FileManager.default.fileExists(atPath: source.path))

        // A second export never overwrites the first.
        document.format = .gif
        let gif = try #require(try await document.export()?.fileURL)
        #expect(gif.lastPathComponent == "Recording 2026-09-19 14.05.02 trimmed.gif")
        #expect(document.exportProgress == nil)
        let again = try #require(try await { document.format = .mp4; return try await document.export()?.fileURL }())
        #expect(again.lastPathComponent == "Recording 2026-09-19 14.05.02 trimmed 2.mp4")
    }
}
