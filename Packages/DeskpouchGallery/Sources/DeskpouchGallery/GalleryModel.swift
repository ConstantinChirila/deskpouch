import DeskpouchCore
import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "gallery")

/// What the gallery window shows: the rows matching the filters (paged), the selection, and delete. The views
/// read it and call it; nothing here draws.
@MainActor
@Observable
public final class GalleryModel {
    static let pageSize = 50
    /// Deleting more rows than this asks first.
    static let confirmAbove = 5

    public private(set) var items: [HistoryItem] = []
    /// Rows matching the filters, loaded or not.
    public private(set) var total = 0
    /// Per kind, with every filter but the kind applied: what each chip would show.
    public private(set) var counts: [HistoryKind: Int] = [:]
    public var query = HistoryQuery() {
        didSet { if query != oldValue { reload() } }
    }
    private(set) var selection = GallerySelection()
    /// Rows waiting for the "Move N items to the Trash?" answer.
    public private(set) var pendingDelete: [UUID]?

    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let trash: (URL) throws -> Void

    /// `trash` moves a file to the Trash; tests pass a recorder.
    public init(store: HistoryStore, trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.store = store
        self.trash = trash
        reload()
    }

    private var order: [UUID] { items.map(\.id) }

    // MARK: Loading

    /// First page for the current filters. Selected rows that no longer match are dropped from the selection.
    public func reload() {
        load(limit: Self.pageSize)
    }

    /// A capture was logged (or a row changed elsewhere): the same stretch of the list again, selection kept.
    public func refresh() {
        load(limit: max(Self.pageSize, items.count))
    }

    private func load(limit: Int) {
        do {
            items = try store.items(query, limit: limit, offset: 0)
            total = try store.count(query)
            counts = try store.countsByKind(query)
        } catch {
            log.error("load failed: \(String(describing: error), privacy: .public)")
        }
        selection.prune(to: order)
        if let pending = pendingDelete, Set(pending).isDisjoint(with: order) { pendingDelete = nil }
    }

    public var hasMore: Bool { items.count < total }

    /// Called as the last rows scroll into view.
    public func loadMore() {
        guard hasMore else { return }
        do {
            let next = try store.items(query, limit: Self.pageSize, offset: items.count)
            let known = Set(order)
            items += next.filter { !known.contains($0.id) }
        } catch {
            log.error("load more failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Selection

    public var selectedIDs: Set<UUID> { selection.ids }
    public var selectedItems: [HistoryItem] { items.filter { selection.ids.contains($0.id) } }
    /// The row in the preview.
    public var focused: HistoryItem? { selection.focus.flatMap { id in items.first { $0.id == id } } }

    /// The rows just above and below the one in the preview, which the preview loads ahead of time.
    public var neighbours: [HistoryItem] {
        guard let focus = selection.focus, let index = items.firstIndex(where: { $0.id == focus }) else { return [] }
        return [index + 1, index - 1].filter(items.indices.contains).map { items[$0] }
    }

    public func click(_ id: UUID, command: Bool, shift: Bool) {
        selection.click(id, in: order, command: command, shift: shift)
    }

    public func move(by delta: Int, extending: Bool) {
        selection.move(by: delta, in: order, extending: extending)
        if selection.focus == items.last?.id { loadMore() }
    }

    public func selectAll() {
        selection.selectAll(in: order)
    }

    /// Opened from a Recent row: that row, with the filters out of its way when they hide it.
    public func show(_ id: UUID) {
        if !order.contains(id) {
            query = HistoryQuery()
        }
        if order.contains(id) { selection.set(id) }
    }

    // MARK: Delete

    /// ⌘⌫ and the Delete button: straight away for a few rows, after a confirm for many.
    public func requestDelete() {
        let ids = order.filter { selection.ids.contains($0) }
        guard !ids.isEmpty else { return }
        if ids.count > Self.confirmAbove {
            pendingDelete = ids
        } else {
            delete(ids)
        }
    }

    public func confirmDelete() {
        guard let ids = pendingDelete else { return }
        pendingDelete = nil
        delete(ids)
    }

    public func cancelDelete() {
        pendingDelete = nil
    }

    /// Rows go, their own files go to the Trash (recoverable), thumbnails go. A file that is already gone is
    /// not an error. The selection lands on the next row.
    private func delete(_ ids: [UUID]) {
        let next = selection.successor(in: order)
        do {
            for file in try store.delete(ids: ids) where FileManager.default.fileExists(atPath: file.path) {
                do {
                    try trash(file)
                } catch {
                    log.error("trash failed for \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        } catch {
            log.error("delete failed: \(String(describing: error), privacy: .public)")
        }
        refresh()
        selection.set(next.flatMap { order.contains($0) ? $0 : nil })
    }

    // MARK: Star

    /// S: stars the selection, or clears the stars when every selected row already has one.
    public func toggleStar() {
        let selected = selectedItems
        guard !selected.isEmpty else { return }
        let star = !selected.allSatisfy(\.starred)
        do {
            try store.setStarred(star, ids: selected.map(\.id))
        } catch {
            log.error("star failed: \(String(describing: error), privacy: .public)")
        }
        refresh()
    }
}
