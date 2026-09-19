import DeskpouchCore
import Foundation
import Testing
@testable import DeskpouchGallery

@MainActor
struct GalleryModelTests {
    final class Trash {
        var files: [URL] = []
    }

    /// `count` screenshot rows, oldest first in `ids`, each pointing at a real temporary file.
    static func seeded(_ count: Int, folder: URL) throws -> (store: HistoryStore, ids: [UUID]) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try HistoryStore.inMemory()
        var ids: [UUID] = []
        for index in 0..<count {
            let id = UUID()
            ids.append(id)
            let file = folder.appending(path: "Screenshot \(index).png")
            try Data([1]).write(to: file)
            try store.record(HistoryItem(
                id: id, toolID: "screenshot", createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                text: nil, fileURL: file, duration: nil, pastedInto: nil, kind: .screenshot
            ))
        }
        return (store, ids)
    }

    static func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "gallery-tests-\(UUID().uuidString)")
    }

    @Test func loadsAPageAndMoreOnDemand() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, ids) = try Self.seeded(60, folder: folder)
        let model = GalleryModel(store: store)
        #expect(model.items.count == 50)
        #expect(model.total == 60)
        #expect(model.items.first?.id == ids.last)
        #expect(model.hasMore)
        model.loadMore()
        #expect(model.items.count == 60)
        #expect(!model.hasMore)
        #expect(model.counts == [.screenshot: 60])
    }

    @Test func deletingAFewRowsTrashesTheirFilesAndSelectsTheNext() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, ids) = try Self.seeded(5, folder: folder)
        let trash = Trash()
        let model = GalleryModel(store: store) { trash.files.append($0) }
        // Newest first: ids[4], ids[3], ... Select the second and third rows.
        model.click(ids[3], command: false, shift: false)
        model.click(ids[2], command: false, shift: true)
        model.requestDelete()
        #expect(model.pendingDelete == nil)
        #expect(trash.files.map(\.lastPathComponent).sorted() == ["Screenshot 2.png", "Screenshot 3.png"])
        #expect(model.items.map(\.id) == [ids[4], ids[1], ids[0]])
        #expect(model.selectedIDs == [ids[1]])
        #expect(model.total == 3)
    }

    @Test func manyRowsAskFirst() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, _) = try Self.seeded(8, folder: folder)
        let trash = Trash()
        let model = GalleryModel(store: store) { trash.files.append($0) }
        model.selectAll()
        model.requestDelete()
        #expect(model.pendingDelete?.count == 8)
        #expect(trash.files.isEmpty)
        model.cancelDelete()
        #expect(model.items.count == 8)
        model.requestDelete()
        model.confirmDelete()
        #expect(trash.files.count == 8)
        #expect(model.items.isEmpty)
        #expect(model.selectedIDs.isEmpty)
    }

    @Test func aFileThatIsAlreadyGoneIsNotTrashed() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, ids) = try Self.seeded(2, folder: folder)
        try FileManager.default.removeItem(at: folder.appending(path: "Screenshot 1.png"))
        let trash = Trash()
        let model = GalleryModel(store: store) { trash.files.append($0) }
        model.click(ids[1], command: false, shift: false)
        model.requestDelete()
        #expect(trash.files.isEmpty)
        #expect(model.items.map(\.id) == [ids[0]])
    }

    @Test func aNewCaptureAppearsWithoutTakingTheSelection() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, ids) = try Self.seeded(3, folder: folder)
        let model = GalleryModel(store: store)
        model.click(ids[1], command: false, shift: false)
        let fresh = UUID()
        try store.record(HistoryItem(id: fresh, toolID: "voice", createdAt: Date(), text: "hello", fileURL: nil, duration: nil, pastedInto: nil))
        model.refresh()
        #expect(model.items.first?.id == fresh)
        #expect(model.selectedIDs == [ids[1]])
        #expect(model.focused?.id == ids[1])
    }

    @Test func aFilterChangeDropsSelectedRowsThatNoLongerMatch() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, ids) = try Self.seeded(3, folder: folder)
        let note = UUID()
        try store.record(HistoryItem(id: note, toolID: "voice", createdAt: Date(), text: "hello", fileURL: nil, duration: nil, pastedInto: nil))
        let model = GalleryModel(store: store)
        model.selectAll()
        model.query.kinds = [.text]
        #expect(model.items.map(\.id) == [note])
        #expect(model.selectedIDs == [note])
        // The chips still count what the other kinds would show.
        #expect(model.counts == [.text: 1, .screenshot: 3])
        _ = ids
    }

    @Test func showingARowClearsFiltersThatHideIt() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, ids) = try Self.seeded(3, folder: folder)
        let model = GalleryModel(store: store)
        model.query.kinds = [.text]
        #expect(model.items.isEmpty)
        model.show(ids[0])
        #expect(model.query == HistoryQuery())
        #expect(model.focused?.id == ids[0])
    }

    @Test func missingFilesAreFoundAndCleanedUpOnlyAfterAConfirm() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, ids) = try Self.seeded(4, folder: folder)
        let note = UUID()
        try store.record(HistoryItem(id: note, toolID: "voice", createdAt: Date(timeIntervalSince1970: 1), text: "hello", fileURL: nil, duration: nil, pastedInto: nil))
        try FileManager.default.removeItem(at: folder.appending(path: "Screenshot 0.png"))
        try FileManager.default.removeItem(at: folder.appending(path: "Screenshot 2.png"))
        let trash = Trash()
        let model = GalleryModel(store: store) { trash.files.append($0) }
        await model.checkFiles()
        // A row without a file is never missing.
        #expect(model.missing == [ids[0], ids[2]])

        model.requestCleanUp()
        #expect(model.pendingDelete == [ids[2], ids[0]])
        #expect(model.pendingIsCleanUp)
        model.cancelDelete()
        #expect(model.items.count == 5)

        // The file of one row comes back before the answer: the row goes, the file is not trashed.
        try Data([1]).write(to: folder.appending(path: "Screenshot 2.png"))
        model.requestCleanUp()
        model.confirmDelete()
        #expect(trash.files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Screenshot 2.png").path))
        #expect(model.items.map(\.id) == [ids[3], ids[1], note])
        await model.checkFiles()
        #expect(model.missing.isEmpty)
    }

    @Test func anUnreachableFolderMarksRowsMissingButNothingIsRemovedByItself() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, _) = try Self.seeded(3, folder: folder)
        let model = GalleryModel(store: store, trash: { _ in }, fileExists: { _ in false })
        await model.checkFiles()
        #expect(model.missing.count == 3)
        #expect(model.items.count == 3)
        #expect(model.pendingDelete == nil)
    }

    @Test func theDatePresetNarrowsAndShowingARowClearsIt() throws {
        let store = try HistoryStore.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 15)))
        func add(daysAgo: Int) throws -> UUID {
            let id = UUID()
            try store.record(HistoryItem(
                id: id, toolID: "voice", createdAt: now.addingTimeInterval(-Double(daysAgo) * 86_400), text: "note \(daysAgo)",
                fileURL: nil, duration: nil, pastedInto: daysAgo == 0 ? "Notes" : nil
            ))
            return id
        }
        let today = try add(daysAgo: 0)
        let lastWeek = try add(daysAgo: 5)
        let old = try add(daysAgo: 40)
        let model = GalleryModel(store: store, now: { now }, calendar: calendar)
        #expect(model.items.count == 3)
        #expect(!model.isFiltered)
        #expect(model.pastedApps == ["Notes"])

        model.datePreset = .today
        #expect(model.items.map(\.id) == [today])
        #expect(model.isFiltered)
        model.datePreset = .week
        #expect(model.items.map(\.id) == [today, lastWeek])
        #expect(model.counts == [.text: 2])

        model.query.starredOnly = true
        #expect(model.items.isEmpty)
        model.show(old)
        #expect(model.datePreset == .any)
        #expect(model.focused?.id == old)

        model.query.pastedInto = "Notes"
        #expect(model.items.map(\.id) == [today])
    }

    @Test func starTogglesTheWholeSelection() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, ids) = try Self.seeded(3, folder: folder)
        let model = GalleryModel(store: store)
        model.click(ids[2], command: false, shift: false)
        model.toggleStar()
        model.selectAll()
        // Mixed selection: everything gets a star.
        model.toggleStar()
        #expect(model.items.map(\.starred) == [true, true, true])
        model.toggleStar()
        #expect(model.items.map(\.starred) == [false, false, false])
    }
}
