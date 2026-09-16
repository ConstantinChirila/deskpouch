import Foundation
import Testing
@testable import DeskpouchCore

@MainActor
struct HistoryPageTests {
    private func item(_ n: Int, tool: String = "voice") -> HistoryItem {
        HistoryItem(id: UUID(), toolID: tool, createdAt: Date(timeIntervalSince1970: TimeInterval(n)),
                    text: "item \(n)", fileURL: nil, duration: 1, pastedInto: nil)
    }

    private func store(_ count: Int) throws -> HistoryStore {
        let store = try HistoryStore.inMemory()
        for n in 1...count { try store.record(item(n)) }
        return store
    }

    @Test func firstThenMorePagesThroughEverything() throws {
        let store = try store(5)
        var page = try store.page(.first, after: HistoryPage(), query: "", toolID: nil, pageSize: 2)
        #expect(page.items.map(\.text) == ["item 5", "item 4"])
        #expect(page.matches == 5)
        #expect(page.hasMore)
        page = try store.page(.more, after: page, query: "", toolID: nil, pageSize: 2)
        page = try store.page(.more, after: page, query: "", toolID: nil, pageSize: 2)
        #expect(page.items.map(\.text) == ["item 5", "item 4", "item 3", "item 2", "item 1"])
        #expect(!page.hasMore)
    }

    @Test func rowLoggedWhilePagedIsNotShownTwice() throws {
        let store = try store(4)
        var page = try store.page(.first, after: HistoryPage(), query: "", toolID: nil, pageSize: 2)
        try store.record(item(10))
        page = try store.page(.more, after: page, query: "", toolID: nil, pageSize: 2)
        let ids = page.items.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(page.items.map(\.text) == ["item 4", "item 3", "item 2"])
    }

    @Test func refreshKeepsLoadedDepthAndPicksUpNewRows() throws {
        let store = try store(5)
        var page = try store.page(.first, after: HistoryPage(), query: "", toolID: nil, pageSize: 2)
        page = try store.page(.more, after: page, query: "", toolID: nil, pageSize: 2)
        try store.record(item(10))
        page = try store.page(.refresh, after: page, query: "", toolID: nil, pageSize: 2)
        #expect(page.items.map(\.text) == ["item 10", "item 5", "item 4", "item 3"])
        #expect(page.matches == 6)
    }

    @Test func filterAppliesToItemsAndCount() throws {
        let store = try store(2)
        try store.record(item(3, tool: "screen"))
        let page = try store.page(.first, after: HistoryPage(), query: "", toolID: "screen", pageSize: 10)
        #expect(page.items.map(\.text) == ["item 3"])
        #expect(page.matches == 1)
    }
}
