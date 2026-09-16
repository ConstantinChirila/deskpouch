import Foundation

/// One screen of the History view: the rows loaded so far and how many rows match in total.
public struct HistoryPage: Sendable, Equatable {
    public var items: [HistoryItem]
    public var matches: Int

    public init(items: [HistoryItem] = [], matches: Int = 0) {
        self.items = items
        self.matches = matches
    }

    public enum Load: Sendable {
        /// First page for a new query or filter.
        case first
        /// Append the next page.
        case more
        /// Re-read everything already shown, e.g. after a new row was logged while the view is open.
        case refresh
    }

    public var hasMore: Bool { items.count < matches }
}

public extension HistoryStore {
    /// Loads `load` on top of `current` for the given query and tool filter.
    /// Paging is by offset, so rows that shifted since the last page (a new capture) are dropped instead of
    /// showing twice; `.refresh` is how the view picks those new rows up.
    func page(
        _ load: HistoryPage.Load, after current: HistoryPage, query: String, toolID: String?, pageSize: Int
    ) throws -> HistoryPage {
        let matches = try count(matching: query, toolID: toolID)
        switch load {
        case .first:
            return HistoryPage(items: try items(matching: query, toolID: toolID, limit: pageSize, offset: 0), matches: matches)
        case .refresh:
            let limit = max(pageSize, current.items.count)
            return HistoryPage(items: try items(matching: query, toolID: toolID, limit: limit, offset: 0), matches: matches)
        case .more:
            let next = try items(matching: query, toolID: toolID, limit: pageSize, offset: current.items.count)
            let seen = Set(current.items.map(\.id))
            return HistoryPage(items: current.items + next.filter { !seen.contains($0.id) }, matches: matches)
        }
    }
}
