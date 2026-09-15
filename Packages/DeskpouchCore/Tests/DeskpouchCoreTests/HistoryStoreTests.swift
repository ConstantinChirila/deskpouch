import Foundation
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
}
