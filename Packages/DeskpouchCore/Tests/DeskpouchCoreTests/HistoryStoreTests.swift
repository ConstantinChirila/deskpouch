import Foundation
import SQLite3
import Testing
@testable import DeskpouchCore

@MainActor
struct HistoryStoreTests {
    private func item(_ text: String?, at seconds: TimeInterval, file: URL? = nil, pastedInto: String? = nil) -> HistoryItem {
        HistoryItem(
            id: UUID(), toolID: "voice", createdAt: Date(timeIntervalSince1970: seconds),
            text: text, fileURL: file, duration: 1.5, pastedInto: pastedInto
        )
    }

    @Test func roundTrip() throws {
        let store = try HistoryStore.inMemory()
        let saved = item("hello there", at: 1000, file: URL(fileURLWithPath: "/tmp/a.mp4"), pastedInto: "Slack")
        try store.record(saved)
        let loaded = try store.recent(limit: 10)
        #expect(loaded == [saved])
        #expect(try store.count() == 1)
    }

    @Test func nilFieldsSurvive() throws {
        let store = try HistoryStore.inMemory()
        let bare = HistoryItem(id: UUID(), toolID: "voice", createdAt: Date(timeIntervalSince1970: 5),
                               text: nil, fileURL: nil, duration: nil, pastedInto: nil)
        try store.record(bare)
        #expect(try store.recent(limit: 1) == [bare])
    }

    @Test func recentIsNewestFirstAndLimited() throws {
        let store = try HistoryStore.inMemory()
        let a = item("a", at: 100)
        let b = item("b", at: 300)
        let c = item("c", at: 200)
        for i in [a, b, c] { try store.record(i) }
        #expect(try store.recent(limit: 2).map(\.text) == ["b", "c"])
        #expect(try store.count() == 3)
    }

    @Test func deleteAndClear() throws {
        let store = try HistoryStore.inMemory()
        let a = item("a", at: 100)
        let b = item("b", at: 200)
        try store.record(a)
        try store.record(b)
        try store.delete(id: a.id)
        #expect(try store.recent(limit: 10) == [b])
        try store.clear()
        #expect(try store.count() == 0)
        #expect(try store.recent(limit: 10).isEmpty)
    }

    @Test func recordingAgainKeepsTheStar() throws {
        let store = try HistoryStore.inMemory()
        let first = item("first", at: 100)
        try store.record(first)
        try store.setStarred(true, ids: [first.id])
        try store.record(HistoryItem(
            id: first.id, toolID: "voice", createdAt: first.createdAt, text: "second", fileURL: nil,
            duration: nil, pastedInto: "Notes"
        ))
        let loaded = try store.recent(limit: 10)
        #expect(loaded.count == 1)
        #expect(loaded.first?.text == "second")
        #expect(loaded.first?.pastedInto == "Notes")
        #expect(loaded.first?.starred == true)
    }

    @Test func persistsToDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "deskpouch-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "nested").appending(path: "history.sqlite")
        let saved = item("persist me", at: 42)
        do {
            let store = try HistoryStore(url: url)
            try store.record(saved)
        }
        let reopened = try HistoryStore(url: url)
        #expect(try reopened.recent(limit: 1) == [saved])
    }

    @Test func kindAndThumbRoundTrip() throws {
        let store = try HistoryStore.inMemory()
        let thumb = URL(fileURLWithPath: "/tmp/thumb-\(UUID().uuidString).jpg")
        let saved = HistoryItem(
            id: UUID(), toolID: "screenshot", createdAt: Date(timeIntervalSince1970: 10),
            text: nil, fileURL: URL(fileURLWithPath: "/tmp/shot.png"), duration: nil,
            pastedInto: nil, kind: .screenshot, thumbURL: thumb
        )
        try store.record(saved)
        let loaded = try store.recent(limit: 1)
        #expect(loaded == [saved])
        #expect(loaded.first?.kind == .screenshot)
        #expect(loaded.first?.thumbURL == thumb)
    }

    @Test func kindDefaultsInferFromWhetherThereIsAFile() throws {
        let store = try HistoryStore.inMemory()
        try store.record(item("a text row", at: 1))
        try store.record(item(nil, at: 2, file: URL(fileURLWithPath: "/tmp/a.mp4")))
        let rows = try store.recent(limit: 10)
        #expect(rows.first { $0.text != nil }?.kind == .text)
        #expect(rows.first { $0.fileURL != nil }?.kind == .recording)
    }

    @Test func deletingARowRemovesItsThumbFile() throws {
        let store = try HistoryStore.inMemory()
        let dir = FileManager.default.temporaryDirectory.appending(path: "deskpouch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let thumb = dir.appending(path: "thumb.jpg")
        try Data([0x1]).write(to: thumb)
        let saved = HistoryItem(
            id: UUID(), toolID: "screenshot", createdAt: Date(), text: nil, fileURL: nil,
            duration: nil, pastedInto: nil, kind: .screenshot, thumbURL: thumb
        )
        try store.record(saved)
        #expect(FileManager.default.fileExists(atPath: thumb.path))
        try store.delete(id: saved.id)
        #expect(!FileManager.default.fileExists(atPath: thumb.path))
    }

    @Test func clearRemovesEveryThumbFile() throws {
        let store = try HistoryStore.inMemory()
        let dir = FileManager.default.temporaryDirectory.appending(path: "deskpouch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let thumbs = (0..<3).map { dir.appending(path: "thumb\($0).jpg") }
        for (i, thumb) in thumbs.enumerated() {
            try Data([UInt8(i)]).write(to: thumb)
            try store.record(HistoryItem(
                id: UUID(), toolID: "screenshot", createdAt: Date(timeIntervalSince1970: Double(i)),
                text: nil, fileURL: nil, duration: nil, pastedInto: nil, kind: .screenshot, thumbURL: thumb
            ))
        }
        try store.clear()
        for thumb in thumbs {
            #expect(!FileManager.default.fileExists(atPath: thumb.path))
        }
    }

    @Test func migratesAnOldSchemaDatabaseAndInfersKind() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "deskpouch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "history.sqlite")

        // Build a database with the schema from before `kind` and `thumb_path` existed.
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        let create = """
            CREATE TABLE results (
                id TEXT PRIMARY KEY, tool_id TEXT NOT NULL, created_at REAL NOT NULL,
                text TEXT, file_path TEXT, duration REAL, pasted_into TEXT
            )
            """
        #expect(sqlite3_exec(handle, create, nil, nil, nil) == SQLITE_OK)
        let textID = UUID().uuidString
        let fileID = UUID().uuidString
        let insertText = "INSERT INTO results (id, tool_id, created_at, text, file_path, duration, pasted_into) " +
            "VALUES ('\(textID)', 'voice', 1000, 'hello there', NULL, NULL, NULL)"
        let insertFile = "INSERT INTO results (id, tool_id, created_at, text, file_path, duration, pasted_into) " +
            "VALUES ('\(fileID)', 'screen', 2000, NULL, '/tmp/a.mp4', 42, NULL)"
        #expect(sqlite3_exec(handle, insertText, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(handle, insertFile, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)

        // Opening through HistoryStore should add the missing columns and backfill kind for both existing rows.
        let store = try HistoryStore(url: url)
        let items = try store.recent(limit: 10)
        #expect(items.count == 2)
        let textRow = try #require(items.first { $0.id.uuidString.lowercased() == textID.lowercased() })
        let fileRow = try #require(items.first { $0.id.uuidString.lowercased() == fileID.lowercased() })
        #expect(textRow.kind == .text)
        #expect(textRow.thumbURL == nil)
        #expect(fileRow.kind == .recording)
        #expect(fileRow.thumbURL == nil)

        // Reopening (columns already present) must not fail or reset anything.
        let reopened = try HistoryStore(url: url)
        #expect(try reopened.count() == 2)
    }

    @Test func searchFilterAndPaging() throws {
        let store = try HistoryStore.inMemory()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func add(_ i: Int, tool: String, text: String?, file: String?) throws {
            try store.record(HistoryItem(id: UUID(), toolID: tool, createdAt: base.addingTimeInterval(Double(i)), text: text,
                                         fileURL: file.map { URL(fileURLWithPath: $0) }, duration: nil, pastedInto: nil))
        }
        try add(1, tool: "voice", text: "move standup to ten", file: nil)
        try add(2, tool: "screen", text: nil, file: "/tmp/Recording 10.32.mp4")
        try add(3, tool: "voice", text: "send the invoice 100% today", file: nil)
        try add(4, tool: "voice", text: "ship the plan", file: nil)

        #expect(try store.count(matching: "", toolID: nil) == 4)
        #expect(try store.count(matching: "", toolID: "voice") == 3)
        #expect(try store.items(matching: "recording", toolID: nil, limit: 10, offset: 0).map(\.toolID) == ["screen"])
        #expect(try store.items(matching: "100%", toolID: "voice", limit: 10, offset: 0).map(\.text) == ["send the invoice 100% today"])
        #expect(try store.items(matching: "%", toolID: nil, limit: 10, offset: 0).count == 1)
        let page1 = try store.items(matching: "", toolID: "voice", limit: 2, offset: 0)
        let page2 = try store.items(matching: "", toolID: "voice", limit: 2, offset: 2)
        #expect(page1.map(\.text) == ["ship the plan", "send the invoice 100% today"])
        #expect(page2.map(\.text) == ["move standup to ten"])
    }
}

@MainActor
struct HistoryMetaTests {
    @Test func metaRoundTrips() throws {
        let store = try HistoryStore.inMemory()
        let picked = HistoryItem(
            id: UUID(), toolID: "color", createdAt: Date(timeIntervalSince1970: 10),
            text: "oklch(0.769 0.165 70.1)", fileURL: nil, duration: nil, pastedInto: nil,
            kind: .color, meta: ResultMeta(srgb: "#f59e0b")
        )
        let shot = HistoryItem(
            id: UUID(), toolID: "screenshot", createdAt: Date(timeIntervalSince1970: 20),
            text: nil, fileURL: URL(fileURLWithPath: "/tmp/a.png"), duration: nil, pastedInto: nil,
            kind: .screenshot, meta: ResultMeta(display: 1, rect: [160, 140, 1040, 760])
        )
        try store.record(picked)
        try store.record(shot)
        #expect(try store.recent(limit: 10) == [shot, picked])
        #expect(try store.recent(limit: 10).first?.meta?.rect == [160, 140, 1040, 760])
    }

    @Test func emptyMetaIsNotStored() throws {
        let store = try HistoryStore.inMemory()
        let row = HistoryItem(
            id: UUID(), toolID: "voice", createdAt: Date(timeIntervalSince1970: 1),
            text: "hi", fileURL: nil, duration: nil, pastedInto: nil, meta: ResultMeta()
        )
        try store.record(row)
        #expect(try store.recent(limit: 1).first?.meta == nil)
    }

    @Test func unknownJSONReadsAsNoMeta() {
        #expect(ResultMeta(json: "not json") == nil)
        #expect(ResultMeta(json: nil) == nil)
        #expect(ResultMeta(json: "{}") == ResultMeta())
        #expect(ResultMeta(srgb: "#f59e0b").json == ##"{"srgb":"#f59e0b"}"##)
    }

    /// A database written by a build from before `meta` existed: opening it adds the column and keeps the rows.
    @Test func opensADatabaseWithoutTheMetaColumn() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "HistoryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "history.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var handle: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
        let old = """
        CREATE TABLE results (
            id TEXT PRIMARY KEY, tool_id TEXT NOT NULL, created_at REAL NOT NULL, text TEXT,
            file_path TEXT, duration REAL, pasted_into TEXT, kind TEXT NOT NULL DEFAULT 'text', thumb_path TEXT
        );
        INSERT INTO results (id, tool_id, created_at, text, kind)
        VALUES ('\(UUID().uuidString)', 'voice', 1000, 'from an older build', 'text');
        """
        #expect(sqlite3_exec(handle, old, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)

        let store = try HistoryStore(url: url)
        let existing = try store.recent(limit: 10)
        #expect(existing.count == 1)
        #expect(existing.first?.text == "from an older build")
        #expect(existing.first?.meta == nil)
        let picked = HistoryItem(
            id: UUID(), toolID: "color", createdAt: Date(timeIntervalSince1970: 2000), text: "#f59e0b",
            fileURL: nil, duration: nil, pastedInto: nil, kind: .color, meta: ResultMeta(srgb: "#f59e0b")
        )
        try store.record(picked)
        #expect(try store.recent(limit: 1) == [picked])
    }
}
