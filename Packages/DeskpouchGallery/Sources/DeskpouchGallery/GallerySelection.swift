import Foundation

/// Which rows are selected, in a list whose order is handed in with every change. Pure, so the click and arrow
/// rules are unit tested. `focus` is the row the preview shows; `anchor` is where a Shift range starts.
struct GallerySelection: Equatable, Sendable {
    private(set) var ids: Set<UUID> = []
    private(set) var anchor: UUID?
    private(set) var focus: UUID?

    var isEmpty: Bool { ids.isEmpty }

    /// One row, nothing else.
    mutating func set(_ id: UUID?) {
        ids = id.map { [$0] } ?? []
        anchor = id
        focus = id
    }

    /// A click: plain replaces, ⌘ toggles the row, Shift selects from the anchor to the row.
    mutating func click(_ id: UUID, in order: [UUID], command: Bool, shift: Bool) {
        if shift, let anchor, let range = Self.range(from: anchor, to: id, in: order) {
            ids = Set(range)
            focus = id
        } else if command {
            if ids.contains(id) {
                ids.remove(id)
                // The preview moves to a row that is still selected: the nearest one below, else above.
                focus = Self.nearest(to: id, among: ids, in: order)
                anchor = focus
            } else {
                ids.insert(id)
                anchor = id
                focus = id
            }
        } else {
            set(id)
        }
    }

    /// Arrow keys. With nothing selected the first press lands on the first row (or the last, going up).
    mutating func move(by delta: Int, in order: [UUID], extending: Bool) {
        guard !order.isEmpty, delta != 0 else { return }
        guard let focus, let index = order.firstIndex(of: focus) else {
            set(delta > 0 ? order.first : order.last)
            return
        }
        let target = order[min(max(index + delta, 0), order.count - 1)]
        if extending, let anchor, let range = Self.range(from: anchor, to: target, in: order) {
            ids = Set(range)
            self.focus = target
        } else {
            set(target)
        }
    }

    mutating func selectAll(in order: [UUID]) {
        guard !order.isEmpty else { return }
        ids = Set(order)
        anchor = order.first
        focus = focus.flatMap { order.contains($0) ? $0 : nil } ?? order.first
    }

    /// Drops rows that are no longer listed (a filter changed, another window deleted them).
    mutating func prune(to order: [UUID]) {
        let listed = Set(order)
        ids.formIntersection(listed)
        if let focus, !listed.contains(focus) { self.focus = order.first { ids.contains($0) } }
        if let anchor, !listed.contains(anchor) { self.anchor = focus }
    }

    /// The row to select once the selected ones are deleted: the next one down, else the one above, else none.
    func successor(in order: [UUID]) -> UUID? {
        guard let last = order.lastIndex(where: { ids.contains($0) }),
              let first = order.firstIndex(where: { ids.contains($0) }) else { return focus }
        if let below = order[(last + 1)...].first { return below }
        return order[..<first].last { !ids.contains($0) }
    }

    private static func range(from a: UUID, to b: UUID, in order: [UUID]) -> ArraySlice<UUID>? {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return nil }
        return order[min(i, j)...max(i, j)]
    }

    private static func nearest(to id: UUID, among ids: Set<UUID>, in order: [UUID]) -> UUID? {
        guard let index = order.firstIndex(of: id) else { return order.first { ids.contains($0) } }
        return order[index...].first { ids.contains($0) } ?? order[..<index].last { ids.contains($0) }
    }
}
