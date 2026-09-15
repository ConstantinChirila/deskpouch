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
