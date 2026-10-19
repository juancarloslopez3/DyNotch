import CoreGraphics
import Foundation

/// A widget the Home tab can show.
nonisolated enum HomeWidget: String, CaseIterable, Identifiable, Codable, Sendable {
    case media, clock, weather, calendar, reminders, battery, timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: String(localized: "Now Playing")
        case .clock: String(localized: "Clock")
        case .weather: String(localized: "Weather")
        case .calendar: String(localized: "Calendar")
        case .reminders: String(localized: "Reminders")
        case .battery: String(localized: "Battery")
        case .timer: String(localized: "Timer")
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .clock: "clock"
        case .weather: "cloud.sun"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .battery: "battery.75percent"
        case .timer: "timer"
        }
    }

    /// The clock always stays on the Home tab; every other widget can come off it.
    var isRemovable: Bool { self != .clock }

    /// Its large card looks right in a narrow column.
    var suitsNarrowColumn: Bool {
        switch self {
        case .media, .calendar, .reminders: false
        default: true
        }
    }
}

/// A card on the Home tab: a large one, or a small one a single row high. A large card shows
/// one widget, or Calendar and Reminders together; a small one shows one widget.
nonisolated struct HomeCard: Codable, Hashable, Identifiable, Sendable {
    var widgets: [HomeWidget]
    var isLarge: Bool

    init(widgets: [HomeWidget], isLarge: Bool) {
        self.widgets = widgets
        self.isLarge = isLarge
    }

    static func large(_ widget: HomeWidget) -> HomeCard { HomeCard(widgets: [widget], isLarge: true) }
    static func small(_ widget: HomeWidget) -> HomeCard { HomeCard(widgets: [widget], isLarge: false) }
    /// Calendar and Reminders sharing a large card.
    static let agenda = HomeCard(widgets: [.calendar, .reminders], isLarge: true)

    /// A widget is on one card at most, so its first tells the card apart.
    var id: HomeWidget { widgets.first ?? .media }

    /// "Clock", or "Calendar & Reminders" for the two sharing a card.
    var title: String { widgets.map(\.title).joined(separator: String(localized: " & ", comment: "Joins the widgets sharing a card: Calendar & Reminders")) }

    var symbol: String { widgets.count > 1 ? "calendar.badge.checkmark" : widgets.first?.symbol ?? "square.dashed" }

    /// Whether the card can come off the Home tab: none of its widgets has to stay.
    var isRemovable: Bool { widgets.allSatisfy(\.isRemovable) }

    private enum CodingKeys: String, CodingKey {
        case widgets, isLarge
    }

    /// Widgets this version doesn't know are skipped rather than losing the whole layout.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgets = try container.decode([String].self, forKey: .widgets).compactMap(HomeWidget.init(rawValue:))
        isLarge = try container.decode(Bool.self, forKey: .isLarge)
    }
}

/// How much of its column a large card has.
nonisolated enum HomeCardHeight: Hashable, Sendable {
    /// All of it.
    case full
    /// All but a row of small widgets.
    case short
    /// About half: beside another large card, or between two rows of small widgets.
    case half
}

/// How a card is drawn: large, or on a single row.
nonisolated enum HomeCardStyle: Hashable, Sendable {
    case large(HomeCardHeight)
    /// Only its essentials when it's narrow.
    case small(isNarrow: Bool)
}

/// One column of the Home tab: cards, top to bottom, in any order. Large cards share what the
/// small ones leave. Next to a large card, small cards beside each other sit side by side on
/// one row; on their own, small cards stack to fill the column, and show large while there's
/// room for that.
nonisolated struct HomeColumn: Codable, Hashable, Identifiable, Sendable {
    /// Stays with the column as it's moved around.
    var id: Int
    var cards: [HomeCard]

    init(id: Int, cards: [HomeCard] = []) {
        self.id = id
        self.cards = cards
    }

    var isEmpty: Bool { cards.isEmpty }

    func contains(_ widget: HomeWidget) -> Bool { cards.contains { $0.widgets.contains(widget) } }

    var largeCount: Int { cards.count(where: \.isLarge) }
    var smallCount: Int { cards.count { !$0.isLarge } }

    /// Two large cards fit in a column, or one with up to two small ones, or three small ones.
    var fits: Bool {
        switch largeCount {
        case 0: smallCount <= 3
        case 1: smallCount <= 2
        case 2: smallCount == 0
        default: false
        }
    }

    /// The rows, top to bottom: each large card on its own and, next to one, small cards beside
    /// each other together. Without a large card, small ones get a row each.
    var rows: [[HomeCard]] {
        guard largeCount > 0 else { return cards.map { [$0] } }
        var rows: [[HomeCard]] = []
        for card in cards {
            if !card.isLarge, let last = rows.last?.last, !last.isLarge {
                rows[rows.count - 1].append(card)
            } else {
                rows.append([card])
            }
        }
        return rows
    }

    /// Whether `card` shows as a large card: it is one, or it's one of at most two small cards
    /// on their own, which have the room large ones would.
    func showsLarge(_ card: HomeCard) -> Bool {
        card.isLarge || (largeCount == 0 && cards.count <= 2)
    }

    /// How `card` is drawn in this column, `width` wide.
    func style(of card: HomeCard, width: CGFloat) -> HomeCardStyle {
        let rows = rows
        if showsLarge(card) {
            let large = rows.count { showsLarge($0[0]) }
            let small = rows.count - large
            return .large(large > 1 || small > 1 ? .half : small == 1 ? .short : .full)
        }
        let row = rows.first { $0.contains(card) } ?? [card]
        return .small(isNarrow: row.count > 1 && width < HomeLayout.detailedPairWidth)
    }

    /// Whether the cards at `index` and `other` sit side by side: small ones next to each
    /// other, with a large card in the column.
    func areBeside(_ index: Int, _ other: Int) -> Bool {
        guard cards.indices.contains(index), cards.indices.contains(other), abs(index - other) == 1 else { return false }
        return largeCount > 0 && !cards[index].isLarge && !cards[other].isLarge
    }

    /// Small cards, and large ones that look right narrow, suit a narrow column.
    var suitsNarrowWidth: Bool {
        cards.allSatisfy { !showsLarge($0) || $0.widgets.allSatisfy(\.suitsNarrowColumn) }
    }

    /// Calendar and Reminders, both large, share a card: the one the first of them had.
    fileprivate mutating func joinAgenda() {
        let agenda = cards.indices.filter {
            cards[$0].isLarge && cards[$0].widgets.count == 1 && [.calendar, .reminders].contains(cards[$0].id)
        }
        guard agenda.count == 2 else { return }
        cards[agenda[0]] = .agenda
        cards.remove(at: agenda[1])
    }

    private enum CodingKeys: String, CodingKey {
        case id, cards
    }

    /// What versions before cards stored: the large card, and the small widgets under it.
    private enum LegacyKeys: String, CodingKey {
        case large, small
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        if let cards = try container.decodeIfPresent([HomeCard].self, forKey: .cards) {
            self.cards = cards
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            func widgets(_ key: LegacyKeys) throws -> [HomeWidget] {
                try (legacy.decodeIfPresent([String].self, forKey: key) ?? []).compactMap(HomeWidget.init(rawValue:))
            }
            cards = [HomeCard(widgets: try widgets(.large), isLarge: true)] + (try widgets(.small)).map(HomeCard.small)
        }
    }
}

/// What the Home tab shows, and where: three columns, left to right. A column with nothing
/// in it isn't shown, and the others share the room. Each widget appears at most once, and
/// the clock always does.
nonisolated struct HomeLayout: Codable, Equatable, Sendable {
    private(set) var columns: [HomeColumn]

    static let columnCount = 3
    static let columnSpacing: CGFloat = 10
    static let narrowColumnWidth: CGFloat = 168
    /// From this column width up, two small widgets side by side have room for their details.
    static let detailedPairWidth: CGFloat = 288

    /// Now Playing on the left, the clock with the weather under it in the middle and the
    /// agenda on the right.
    static let standard = HomeLayout(columns: [
        HomeColumn(id: 0, cards: [.large(.media)]),
        HomeColumn(id: 1, cards: [.large(.clock), .small(.weather)]),
        HomeColumn(id: 2, cards: [.agenda]),
    ])

    init(columns: [HomeColumn]) {
        self.columns = columns
        sanitize()
    }

    // MARK: - Reading

    /// The columns with something in them, left to right.
    var visibleColumns: [HomeColumn] { columns.filter { !$0.isEmpty } }

    func column(_ id: Int) -> HomeColumn? { columns.first { $0.id == id } }

    func contains(_ widget: HomeWidget) -> Bool { columns.contains { $0.contains(widget) } }

    func isLarge(_ widget: HomeWidget) -> Bool {
        columns.contains { $0.cards.contains { $0.isLarge && $0.widgets.contains(widget) } }
    }

    /// The width `column` gets, or nil to share what the others leave. With three columns
    /// showing, the ones that suit it are narrow, as long as another column takes the rest.
    func fixedWidth(of column: HomeColumn) -> CGFloat? {
        let shown = visibleColumns
        guard shown.count == Self.columnCount, column.suitsNarrowWidth,
              !shown.allSatisfy(\.suitsNarrowWidth) else { return nil }
        return Self.narrowColumnWidth
    }

    /// The width `column` gets out of `width`, the room the shown columns share.
    func width(of column: HomeColumn, sharing width: CGFloat) -> CGFloat {
        if let fixed = fixedWidth(of: column) { return fixed }
        let shown = visibleColumns
        let fixed = shown.compactMap { fixedWidth(of: $0) }
        let free = width - Self.columnSpacing * CGFloat(shown.count - 1) - fixed.reduce(0, +)
        return free / CGFloat(max(shown.count - fixed.count, 1))
    }

    // MARK: - Editing

    /// Whether `widget` can go at the bottom of column `id`, large or small, coming from
    /// wherever it is now.
    func canAdd(_ widget: HomeWidget, large: Bool, to id: Int) -> Bool {
        column(id)?.contains(widget) == false && adding(widget, large: large, to: id) != nil
    }

    /// Puts `widget` at the bottom of column `id`, moving it from wherever it was. Calendar or
    /// Reminders added large next to the other joins its card.
    mutating func add(_ widget: HomeWidget, large: Bool, to id: Int) {
        guard canAdd(widget, large: large, to: id), let layout = adding(widget, large: large, to: id) else { return }
        self = layout
    }

    /// Whether a small widget can turn large: where it is if its column has room, or else
    /// trading places with the large card there.
    func canMakeLarge(_ widget: HomeWidget) -> Bool { madeLarge(widget) != nil }

    mutating func makeLarge(_ widget: HomeWidget) {
        if let layout = madeLarge(widget) { self = layout }
    }

    /// Whether large `widgets` can all turn small where they are. One sharing a card leaves it.
    func canMakeSmall(_ widgets: [HomeWidget]) -> Bool { resized(widgets, large: false) != nil }

    mutating func makeSmall(_ widgets: [HomeWidget]) {
        if let layout = resized(widgets, large: false) { self = layout }
    }

    /// Whether `widget`'s card can move a place up or down its column; left or right when
    /// it sits beside another.
    func canMove(_ widget: HomeWidget, by step: Int) -> Bool {
        guard let position = position(of: widget) else { return false }
        return columns[position.column].cards.indices.contains(position.card + step)
    }

    mutating func move(_ widget: HomeWidget, by step: Int) {
        guard canMove(widget, by: step), let position = position(of: widget) else { return }
        columns[position.column].cards.swapAt(position.card, position.card + step)
    }

    /// Takes `widget` off the Home tab, unless it's one that stays.
    mutating func remove(_ widget: HomeWidget) {
        if widget.isRemovable { takeOff(widget) }
    }

    /// Takes `widget` out of its card, for good or to put it somewhere else.
    private mutating func takeOff(_ widget: HomeWidget) {
        guard let position = position(of: widget) else { return }
        columns[position.column].cards[position.card].widgets.removeAll { $0 == widget }
        if columns[position.column].cards[position.card].widgets.isEmpty {
            columns[position.column].cards.remove(at: position.card)
        }
    }

    /// Puts the shown columns in this order; empty ones keep their places.
    mutating func reorder(shown ids: [Int]) {
        let shown = ids.compactMap { column($0) }
        guard shown.count == visibleColumns.count else { return }
        columns = LayoutOrder.rearranged(columns, shown: shown)
    }

    /// Moves a shown column past its neighbour.
    mutating func moveColumn(_ id: Int, by step: Int) {
        var ids = visibleColumns.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + step) else { return }
        ids.swapAt(index, index + step)
        reorder(shown: ids)
    }

    /// The layout with `widgets` (one card's, or a widget that isn't on the Home tab yet) put
    /// in column `id`, `index` cards down among the ones that stay there, large or small; nil
    /// if the column has no room for that. Calendar and Reminders turning small get a card each.
    func placing(_ widgets: [HomeWidget], large: Bool, in id: Int, at index: Int) -> HomeLayout? {
        guard !widgets.isEmpty, let column = columns.firstIndex(where: { $0.id == id }) else { return nil }
        return changed { layout in
            for widget in widgets {
                layout.takeOff(widget)
            }
            let cards = large ? [HomeCard(widgets: widgets, isLarge: true)] : widgets.map(HomeCard.small)
            let index = min(max(index, 0), layout.columns[column].cards.count)
            layout.columns[column].cards.insert(contentsOf: cards, at: index)
        }
    }

    /// `widgets` dropped in column `id` at `index`: at the size asked for where that fits, or
    /// else at the other one. Nil if the column has room for neither.
    func dropping(_ widgets: [HomeWidget], large: Bool, in id: Int, at index: Int) -> HomeLayout? {
        placing(widgets, large: large, in: id, at: index) ?? placing(widgets, large: !large, in: id, at: index)
    }

    // MARK: - Helpers

    /// Where `widget` is: its column's index, and its card's in the column.
    private func position(of widget: HomeWidget) -> (column: Int, card: Int)? {
        for (index, column) in columns.enumerated() {
            if let card = column.cards.firstIndex(where: { $0.widgets.contains(widget) }) {
                return (index, card)
            }
        }
        return nil
    }

    /// The layout after `change`, or nil if a column no longer fits. Calendar and Reminders,
    /// both large in a column, share a card.
    private func changed(_ change: (inout HomeLayout) -> Void) -> HomeLayout? {
        var layout = self
        change(&layout)
        for index in layout.columns.indices {
            layout.columns[index].joinAgenda()
        }
        return layout.columns.allSatisfy(\.fits) ? layout : nil
    }

    private func adding(_ widget: HomeWidget, large: Bool, to id: Int) -> HomeLayout? {
        guard let index = columns.firstIndex(where: { $0.id == id }) else { return nil }
        return changed {
            $0.takeOff(widget)
            $0.columns[index].cards.append(HomeCard(widgets: [widget], isLarge: large))
        }
    }

    /// `widgets` made large or small where they are. One leaving a card it shares gets a card
    /// of its own beside it, on the side it was.
    private func resized(_ widgets: [HomeWidget], large: Bool) -> HomeLayout? {
        guard !widgets.isEmpty, widgets.allSatisfy({ contains($0) && isLarge($0) != large }) else { return nil }
        return changed { layout in
            for widget in widgets {
                guard let position = layout.position(of: widget) else { continue }
                var cards = layout.columns[position.column].cards
                let index = position.card
                if cards[index].widgets.count > 1, let side = cards[index].widgets.firstIndex(of: widget) {
                    cards[index].widgets.remove(at: side)
                    cards.insert(HomeCard(widgets: [widget], isLarge: large), at: index + side)
                } else {
                    cards[index].isLarge = large
                }
                layout.columns[position.column].cards = cards
            }
        }
    }

    /// Small `widget` made large: where it is if there's room, or else trading places with
    /// the column's large card, which goes small.
    private func madeLarge(_ widget: HomeWidget) -> HomeLayout? {
        if let layout = resized([widget], large: true) { return layout }
        guard let position = position(of: widget), !isLarge(widget) else { return nil }
        let column = columns[position.column]
        guard column.largeCount == 1, let large = column.cards.firstIndex(where: \.isLarge),
              column.cards[large].widgets.count == 1 else { return nil }
        return changed {
            $0.columns[position.column].cards.swapAt(position.card, large)
            $0.columns[position.column].cards[position.card].isLarge = false
            $0.columns[position.column].cards[large].isLarge = true
        }
    }

    /// Makes any stored layout one that can be shown: three columns with their own ids, each
    /// widget once, cards that exist and columns that fit, and the clock. What doesn't fit is
    /// left off.
    private mutating func sanitize() {
        var seen: Set<HomeWidget> = []
        var ids: Set<Int> = []
        func newID() -> Int {
            var id = 0
            while ids.contains(id) { id += 1 }
            return id
        }

        var fixed: [HomeColumn] = []
        for var column in columns.prefix(Self.columnCount) {
            if ids.contains(column.id) { column.id = newID() }
            ids.insert(column.id)
            let cards = column.cards
            column.cards = []
            for var card in cards {
                let widgets = card.widgets.filter { !seen.contains($0) }
                card.widgets = card.isLarge && Set(widgets) == [.calendar, .reminders]
                    ? HomeCard.agenda.widgets
                    : Array(widgets.prefix(1))
                guard !card.widgets.isEmpty else { continue }
                var grown = column
                grown.cards.append(card)
                grown.joinAgenda()
                guard grown.fits else { continue }
                column = grown
                seen.formUnion(card.widgets)
            }
            fixed.append(column)
        }
        while fixed.count < Self.columnCount {
            let id = newID()
            ids.insert(id)
            fixed.append(HomeColumn(id: id))
        }
        columns = fixed
        if !contains(.clock) { putBack(.clock) }
    }

    /// Puts a widget that stays on the Home tab back on it: large in a column of its own if one
    /// is empty, or else small at the bottom of the first with room; failing that, in place of
    /// the last card, at its size.
    private mutating func putBack(_ widget: HomeWidget) {
        if let empty = columns.first(where: \.isEmpty), let layout = adding(widget, large: true, to: empty.id) {
            self = layout
            return
        }
        for column in columns {
            if let layout = adding(widget, large: false, to: column.id) {
                self = layout
                return
            }
        }
        guard let index = columns.lastIndex(where: { !$0.isEmpty }) else { return }
        let replaced = columns[index].cards.removeLast()
        columns[index].cards.append(HomeCard(widgets: [widget], isLarge: replaced.isLarge))
    }

    // MARK: - Storage

    private enum CodingKeys: String, CodingKey {
        case columns
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = try container.decode([HomeColumn].self, forKey: .columns)
        sanitize()
    }

    /// The columns older versions stored: three fixed ones in a saved order, and a switch per widget.
    private enum LegacyColumn: String, CaseIterable {
        case media, clock, agenda
    }

    /// The same Home tab as before columns could be filled freely, but with the clock, which
    /// could be switched off then.
    static func migrated(
        columnOrder: [String]?, media: Bool, weather: Bool, calendar: Bool, reminders: Bool
    ) -> HomeLayout {
        let order: [LegacyColumn] = LayoutOrder.complete(columnOrder)
        var layout = HomeLayout(
            columns: order.enumerated().map { id, column in
                switch column {
                case .media: HomeColumn(id: id, cards: [.large(.media)])
                case .clock: HomeColumn(id: id, cards: [.large(.clock), .small(.weather)])
                case .agenda: HomeColumn(id: id, cards: [.agenda])
                }
            }
        )
        let switches: [(HomeWidget, Bool)] = [
            (.media, media), (.weather, weather), (.calendar, calendar), (.reminders, reminders),
        ]
        for (widget, isOn) in switches where !isOn {
            layout.remove(widget)
        }
        return layout
    }
}
