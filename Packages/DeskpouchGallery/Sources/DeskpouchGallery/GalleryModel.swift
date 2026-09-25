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

    public private(set) var items: [HistoryItem] = [] {
        didSet {
            order = items.map(\.id)
            indexByID = Dictionary(items.indices.map { (items[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
    /// The loaded ids in list order, and where each one is in `items`. Kept beside `items` because every visible
    /// tile asks for the focused row.
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var indexByID: [UUID: Int] = [:]
    /// Rows matching the filters, loaded or not.
    public private(set) var total = 0
    /// Per kind, with every filter but the kind applied: what each chip would show.
    public private(set) var counts: [HistoryKind: Int] = [:]
    /// Search text, kinds, starred and pasted-into. The date comes from `datePreset`, worked out at every load so
    /// "Today" is still today after midnight.
    public var query = HistoryQuery() {
        didSet {
            guard query != oldValue else { return }
            var rest = oldValue
            rest.text = query.text
            // Typing reloads once it pauses: every load is a scan of the whole table. Other filters are one click.
            if rest == query, searchDelay > .zero { scheduleSearchReload() } else { reload() }
        }
    }
    public var datePreset: GalleryDatePreset = .any {
        didSet { if datePreset != oldValue { reload() } }
    }
    /// Apps something was pasted into, for the filter's choices.
    public private(set) var pastedApps: [String] = []
    private(set) var selection = GallerySelection()
    /// Rows waiting for the "Move N items to the Trash?" answer.
    public private(set) var pendingDelete: [UUID]?
    /// The prompt is the missing rows' clean-up, not a delete of the selection.
    public private(set) var pendingIsCleanUp = false
    /// Why the last delete left rows behind, until dismissed or the next delete. Nil when all of it went through.
    public private(set) var deleteFailure: String?
    /// Loaded rows whose file is not where it was saved. Checked off the main actor: a save folder can be on a
    /// slow or absent disk.
    public private(set) var missing: Set<UUID> = []

    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let trash: (URL) throws -> Void
    @ObservationIgnored private let fileExists: @Sendable (String) -> Bool
    @ObservationIgnored private var fileCheck: Task<Void, Never>?
    @ObservationIgnored private let searchDelay: Duration
    @ObservationIgnored private var searchReload: Task<Void, Never>?
    /// Rows that were just deleted, so the window can drop their thumbnails.
    @ObservationIgnored var onDeleted: (@MainActor ([HistoryItem]) -> Void)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// `trash` moves a file to the Trash and `fileExists` looks on disk; tests pass their own. `searchDelay` is how
    /// long a change of the search text waits for the next one before it reloads; zero reloads at once.
    public init(
        store: HistoryStore,
        trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        now: @escaping () -> Date = Date.init, calendar: Calendar = .current, searchDelay: Duration = .zero
    ) {
        self.searchDelay = searchDelay
        self.now = now
        self.calendar = calendar
        self.store = store
        self.trash = trash
        self.fileExists = fileExists
        reload()
    }

    /// Any filter is on: the header says "match", the empty state says "nothing matches".
    public var isFiltered: Bool { query != HistoryQuery() || datePreset != .any }

    /// `query` with the date preset's start filled in.
    private var effectiveQuery: HistoryQuery {
        var effective = query
        effective.from = datePreset.start(now: now(), calendar: calendar)
        return effective
    }

    // MARK: Loading

    /// First page for the current filters. Selected rows that no longer match are dropped from the selection.
    public func reload() {
        load(limit: Self.pageSize)
    }

    /// A capture was logged (or a row changed elsewhere): the same stretch of the list again, selection kept.
    public func refresh() {
        load(limit: max(Self.pageSize, items.count))
    }

    private func scheduleSearchReload() {
        searchReload?.cancel()
        searchReload = Task { [weak self, searchDelay] in
            try? await Task.sleep(for: searchDelay)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func load(limit: Int) {
        // Whatever the search text is by now is part of this load.
        searchReload?.cancel()
        searchReload = nil
        do {
            let query = effectiveQuery
            items = try store.items(query, limit: limit, offset: 0)
            total = try store.count(query)
            counts = try store.countsByKind(query)
            pastedApps = try store.pastedIntoApps()
        } catch {
            log.error("load failed: \(String(describing: error), privacy: .public)")
        }
        selection.prune(to: order)
        if let pending = pendingDelete, Set(pending).isDisjoint(with: order) { pendingDelete = nil }
        scheduleFileCheck()
    }

    private func scheduleFileCheck() {
        fileCheck?.cancel()
        fileCheck = Task { [weak self] in await self?.checkFiles() }
    }

    /// Looks for every loaded row's file, off the main actor. Rows without a file are never missing.
    func checkFiles() async {
        let files = items.compactMap { item in item.fileURL.map { (item.id, $0.path) } }
        let exists = fileExists
        let gone = await Task.detached(priority: .utility) {
            Set(files.filter { !exists($0.1) }.map(\.0))
        }.value
        guard !Task.isCancelled else { return }
        missing = gone.intersection(order)
    }

    public var hasMore: Bool { items.count < total }

    /// Called as the last rows scroll into view.
    public func loadMore() {
        guard hasMore else { return }
        do {
            let next = try store.items(effectiveQuery, limit: Self.pageSize, offset: items.count)
            let known = Set(order)
            items += next.filter { !known.contains($0.id) }
            scheduleFileCheck()
        } catch {
            log.error("load more failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Selection

    public var selectedIDs: Set<UUID> { selection.ids }
    public var selectedItems: [HistoryItem] { items.filter { selection.ids.contains($0.id) } }
    /// The row in the preview.
    public var focused: HistoryItem? { selection.focus.flatMap { item($0) } }

    private func item(_ id: UUID) -> HistoryItem? {
        // `items` first, so a view reading this is redrawn when the rows change.
        let items = items
        return indexByID[id].flatMap { items.indices.contains($0) ? items[$0] : nil }
    }

    /// The rows just above and below the one in the preview, which the preview loads ahead of time.
    public var neighbours: [HistoryItem] {
        let items = items
        guard let focus = selection.focus, let index = indexByID[focus] else { return [] }
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
            datePreset = .any
            query = HistoryQuery()
            // Clearing only the search text would wait; this cannot.
            if searchReload != nil { reload() }
        }
        if order.contains(id) { selection.set(id) }
    }

    // MARK: Delete

    /// ⌘⌫ and the Delete button: straight away for a few rows, after a confirm for many.
    public func requestDelete() {
        let ids = order.filter { selection.ids.contains($0) }
        guard !ids.isEmpty else { return }
        if ids.count > Self.confirmAbove {
            pendingIsCleanUp = false
            pendingDelete = ids
        } else {
            delete(ids)
        }
    }

    public func confirmDelete() {
        guard let ids = pendingDelete else { return }
        pendingDelete = nil
        // A clean-up only ever removes rows: a file that came back meanwhile (the disk was plugged in) stays put.
        delete(ids, trashingFiles: !pendingIsCleanUp)
        pendingIsCleanUp = false
    }

    public func cancelDelete() {
        pendingDelete = nil
        pendingIsCleanUp = false
    }

    /// "N missing · Clean up": drops the loaded rows whose files are gone, after a confirm whatever the number.
    /// Never done without asking: the folder may only be unreachable for now.
    public func requestCleanUp() {
        let ids = order.filter { missing.contains($0) }
        guard !ids.isEmpty else { return }
        pendingIsCleanUp = true
        pendingDelete = ids
    }

    /// Files go to the Trash first (recoverable), then the rows and thumbnails of the ones that made it. A file
    /// that is already gone is not an error. A file the Trash refused keeps its row, so nothing is left on disk
    /// with no row pointing at it. The selection lands on the next row, or stays on the rows that were kept.
    /// Rows are read from the store, not the loaded page: a capture landing while the confirm is up can push a
    /// selected row off the page, and its file must still go to the Trash.
    private func delete(_ ids: [UUID], trashingFiles: Bool = true) {
        let next = selection.successor(in: order)
        var removable: [HistoryItem] = []
        var kept: [UUID] = []
        for id in ids {
            let row: HistoryItem?
            do {
                row = try store.item(id: id)
            } catch {
                log.error("delete lookup failed: \(String(describing: error), privacy: .public)")
                kept.append(id)
                continue
            }
            guard let row else { continue }
            if trashingFiles, let file = row.fileURL,
               FileManager.default.fileExists(atPath: file.path) {
                do {
                    try trash(file)
                } catch {
                    log.error("trash failed for \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                    kept.append(id)
                    continue
                }
            }
            removable.append(row)
        }
        deleteFailure = kept.isEmpty ? nil
            : "\(kept.count == 1 ? "1 file" : "\(kept.count) files") could not be moved to the Trash, so \(kept.count == 1 ? "its row was" : "their rows were") kept. Check the folder is reachable and writable, then delete again."
        do {
            try store.delete(ids: removable.map(\.id))
            onDeleted?(removable)
        } catch {
            // The store deletes all or nothing, so every row is still there; the files are in the Trash.
            log.error("delete failed: \(String(describing: error), privacy: .public)")
            if !removable.isEmpty {
                deleteFailure = "The history could not be updated, so the rows are still listed. Their files are in the Trash."
            }
        }
        refresh()
        if kept.isEmpty {
            selection.set(next.flatMap { order.contains($0) ? $0 : nil })
        }
    }

    public func dismissDeleteFailure() {
        deleteFailure = nil
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
