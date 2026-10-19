import Foundation

/// Which shelf items are selected, following Finder's rules for clicks and arrow keys along the
/// shelf's single row.
nonisolated struct ShelfSelection: Equatable {
    private(set) var ids: Set<UUID> = []
    /// Where a ⇧-click or ⇧-arrow range starts.
    private var anchor: UUID?
    /// The item the arrow keys move on from.
    private(set) var cursor: UUID?

    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// A click on `id`: on its own it selects just that item, with ⌘ it adds or removes it, and
    /// with ⇧ it adds everything from the last item clicked to this one.
    mutating func click(_ id: UUID, in order: [UUID], extending: Bool = false, toggling: Bool = false) {
        if toggling {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchor = id
            cursor = id
        } else if extending, let anchor, let range = Self.range(from: anchor, to: id, in: order) {
            ids.formUnion(range)
            cursor = id
        } else {
            select(id)
        }
    }

    /// ← and →: selects the neighbor of the item last moved to, or the first or last item when
    /// nothing is selected. With ⇧ the selection runs from where it started to there instead.
    mutating func move(by step: Int, in order: [UUID], extending: Bool = false) {
        guard !order.isEmpty else { return }
        let target: UUID
        if !ids.isEmpty, let cursor, let index = order.firstIndex(of: cursor) {
            target = order[min(max(index + step, 0), order.count - 1)]
        } else {
            target = step < 0 ? order[order.count - 1] : order[0]
        }
        if extending, !ids.isEmpty, let anchor, let range = Self.range(from: anchor, to: target, in: order) {
            ids = Set(range)
            cursor = target
        } else {
            select(target)
        }
    }

    /// Home and End.
    mutating func moveToEnd(_ forward: Bool, in order: [UUID]) {
        guard let target = forward ? order.last : order.first else { return }
        select(target)
    }

    /// ⌘A. The arrow keys go on from where they were.
    mutating func selectAll(_ order: [UUID]) {
        ids = Set(order)
        if cursor.map(order.contains) != true { cursor = order.first }
        anchor = cursor
    }

    mutating func select(_ id: UUID) {
        ids = [id]
        anchor = id
        cursor = id
    }

    /// Selects `ids`, such as the items just added, keyboard at the first.
    mutating func select(_ ids: [UUID]) {
        guard let first = ids.first else { return }
        self.ids = Set(ids)
        anchor = first
        cursor = first
    }

    mutating func clear() {
        self = ShelfSelection()
    }

    /// Forgets items that are no longer on the shelf.
    mutating func keep(only order: [UUID]) {
        let present = Set(order)
        ids.formIntersection(present)
        if let anchor, !present.contains(anchor) { self.anchor = nil }
        if let cursor, !present.contains(cursor) { self.cursor = nil }
    }

    /// The selected items, in shelf order.
    func ordered(_ order: [UUID]) -> [UUID] {
        order.filter(ids.contains)
    }

    /// What a command on `id` (from its context menu, or by dragging it) acts on: the whole
    /// selection when `id` is part of it, otherwise `id` alone, as in Finder.
    func targets(for id: UUID, in order: [UUID]) -> [UUID] {
        ids.contains(id) ? ordered(order) : [id]
    }

    private static func range(from start: UUID, to end: UUID, in order: [UUID]) -> ArraySlice<UUID>? {
        guard let a = order.firstIndex(of: start), let b = order.firstIndex(of: end) else { return nil }
        return order[min(a, b)...max(a, b)]
    }
}
