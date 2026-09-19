import Foundation
import SQLite3
import Testing
@testable import DeskpouchCore

@MainActor
struct HistoryQueryTests {
    static let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Five rows, one per second: a transcript pasted into Notes, a screenshot, a recording, a GIF, a colour.
    static func seeded() throws -> (store: HistoryStore, ids: [UUID]) {
        let store = try HistoryStore.inMemory()
        let rows: [(String, String?, String?, HistoryKind, String?)] = [
            ("voice", "remember the milk", nil, .text, "Notes"),
            ("screenshot", nil, "/tmp/Screenshot 1.png", .screenshot, nil),
            ("screen", nil, "/tmp/Recording 1.mp4", .recording, nil),
            ("screen", nil, "/tmp/Recording 1 trimmed.gif", .recording, nil),
            ("color", "#f59e0b", nil, .color, "Figma"),
        ]
        var ids: [UUID] = []
        for (index, row) in rows.enumerated() {
            let id = UUID()
            ids.append(id)
            try store.record(HistoryItem(
                id: id, toolID: row.0, createdAt: base.addingTimeInterval(Double(index)), text: row.1,
                fileURL: row.2.map { URL(fileURLWithPath: $0) }, duration: nil, pastedInto: row.4, kind: row.3
            ))
        }
        return (store, ids)
    }

    @Test func theDefaultQueryMatchesEverythingNewestFirst() throws {
        let (store, ids) = try Self.seeded()
        let items = try store.items(HistoryQuery(), limit: 10, offset: 0)
        #expect(items.map(\.id) == ids.reversed())
        #expect(try store.count(HistoryQuery()) == 5)
    }

    @Test func kindsNarrowAndAGIFIsARecording() throws {
        let (store, _) = try Self.seeded()
        let recordings = try store.items(HistoryQuery(kinds: [.recording]), limit: 10, offset: 0)
        #expect(recordings.compactMap { $0.fileURL?.pathExtension } == ["gif", "mp4"])
        #expect(try store.count(HistoryQuery(kinds: [.screenshot, .color])) == 2)
        #expect(try store.count(HistoryQuery(kinds: [])) == 0)
    }

    @Test func dateBoundsIncludeTheStartAndExcludeTheEnd() throws {
        let (store, ids) = try Self.seeded()
        let query = HistoryQuery(from: Self.base.addingTimeInterval(1), before: Self.base.addingTimeInterval(3))
        #expect(try store.items(query, limit: 10, offset: 0).map(\.id) == [ids[2], ids[1]])
    }

    @Test func starredSurvivesAndFilters() throws {
        let (store, ids) = try Self.seeded()
        try store.setStarred(true, ids: [ids[1], ids[4]])
        let starred = try store.items(HistoryQuery(starredOnly: true), limit: 10, offset: 0)
        #expect(starred.map(\.id) == [ids[4], ids[1]])
        #expect(starred.map(\.starred) == [true, true])
        try store.setStarred(false, ids: [ids[4]])
        #expect(try store.count(HistoryQuery(starredOnly: true)) == 1)
        let everything = try store.items(HistoryQuery(), limit: 10, offset: 0)
        #expect(everything.filter(\.starred).map(\.id) == [ids[1]])
    }

    @Test func pastedIntoFilterAndItsChoices() throws {
        let (store, ids) = try Self.seeded()
        #expect(try store.pastedIntoApps() == ["Figma", "Notes"])
        #expect(try store.items(HistoryQuery(pastedInto: "Notes"), limit: 10, offset: 0).map(\.id) == [ids[0]])
    }

    @Test func filtersCombineWithSearch() throws {
        let (store, ids) = try Self.seeded()
        let query = HistoryQuery(text: "recording", kinds: [.recording], from: Self.base.addingTimeInterval(3))
        #expect(try store.items(query, limit: 10, offset: 0).map(\.id) == [ids[3]])
        // A colour is found by its value.
        #expect(try store.items(HistoryQuery(text: "f59e"), limit: 10, offset: 0).map(\.id) == [ids[4]])
    }

    @Test func countsByKindIgnoreTheKindFilterButKeepTheRest() throws {
        let (store, _) = try Self.seeded()
        let all = try store.countsByKind(HistoryQuery(kinds: [.text]))
        #expect(all == [.text: 1, .screenshot: 1, .recording: 2, .color: 1])
        let searched = try store.countsByKind(HistoryQuery(text: "Recording"))
        #expect(searched == [.recording: 2])
    }

    @Test func deleteHandsBackTheFilesAndDropsTheRows() throws {
        let (store, ids) = try Self.seeded()
        let files = try store.delete(ids: [ids[0], ids[2], ids[3]])
        #expect(files.map(\.lastPathComponent) == ["Recording 1.mp4", "Recording 1 trimmed.gif"])
        #expect(try store.items(HistoryQuery(), limit: 10, offset: 0).map(\.id) == [ids[4], ids[1]])
        // Unknown ids are not an error.
        #expect(try store.delete(ids: [UUID()]).isEmpty)
    }

    @Test func aThumbnailCanBeAddedLater() throws {
        let (store, ids) = try Self.seeded()
        try store.setThumbnail(URL(fileURLWithPath: "/tmp/thumb.jpg"), id: ids[2])
        let rows = try store.items(HistoryQuery(), limit: 10, offset: 0)
        let row = try #require(rows.first { $0.id == ids[2] })
        #expect(row.thumbURL?.path == "/tmp/thumb.jpg")
    }

    @Test func anOlderDatabaseGainsTheStarredColumn() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "deskpouch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "history.sqlite")

        // The schema as it was with `meta` and before `starred`.
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        let create = """
            CREATE TABLE results (
                id TEXT PRIMARY KEY, tool_id TEXT NOT NULL, created_at REAL NOT NULL, text TEXT, file_path TEXT,
                duration REAL, pasted_into TEXT, kind TEXT NOT NULL DEFAULT 'text', thumb_path TEXT, meta TEXT
            )
            """
        #expect(sqlite3_exec(handle, create, nil, nil, nil) == SQLITE_OK)
        let id = UUID()
        let insert = "INSERT INTO results (id, tool_id, created_at, text, kind) VALUES ('\(id.uuidString)', 'voice', 1000, 'hello', 'text')"
        #expect(sqlite3_exec(handle, insert, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)

        let store = try HistoryStore(url: url)
        #expect(try store.recent(limit: 10).map(\.starred) == [false])
        try store.setStarred(true, ids: [id])
        let reopened = try HistoryStore(url: url)
        #expect(try reopened.recent(limit: 10).map(\.starred) == [true])
    }
}
