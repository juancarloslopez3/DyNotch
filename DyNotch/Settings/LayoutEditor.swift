import SwiftUI

// MARK: - Editor

/// Settings › Layout's picture of the open notch, laid out with the real metrics and scaled to
/// fit, to arrange by dragging: Home widgets up, down, into another column or into an empty
/// one (a slot while dragging); onto the tray under the notch to take them off, all but the
/// clock, and from it to add them; columns by the handle under them, and tabs sideways. Clicking a tab shows it.
struct NotchLayoutEditor: View {
    @Environment(AppServices.self) private var services
    @State private var drag = LayoutDrag()
    @State private var shownTab = NotchTab.home
    /// Resets by itself when a drag ends or is cancelled; `onEnded` only sees the former.
    @GestureState private var isDragging = false

    /// The editor's coordinate space: the pointer and every frame it can land on are measured in it.
    nonisolated static let space = "NotchLayoutEditor"

    var body: some View {
        VStack(spacing: 12) {
            NotchPreview(shownTab: $shownTab)
            WidgetTray()
        }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) {
            LiftedItem()
        }
        .gesture(dragGesture)
        .onChange(of: isDragging) { _, dragging in
            if !dragging { drop() }
        }
        .pointerStyle(drag.item == nil ? nil : .grabActive)
        .environment(drag)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                let layout = services.settings.homeLayout
                if !drag.isTracking {
                    drag.begin(at: value.startLocation, layout: layout, showsHome: shownTab == .home)
                    // A widget from the tray goes on the Home tab, so show that.
                    if case .widget? = drag.item { shownTab = .home }
                }
                drag.move(to: value.location, layout: layout)
            }
    }

    /// Lets go: the lifted copy glides to where it lands, or back where it came from, and the
    /// Home tab changes once it's there.
    private func drop() {
        let settings = services.settings
        guard let landing = drag.end(layout: settings.homeLayout) else { return }
        withAnimation(.notchQuick) {
            drag.land(at: landing.frame)
        } completion: {
            if let layout = landing.layout { settings.homeLayout = layout }
            drag.reset()
        }
    }
}

// MARK: - Dragging

/// What's being dragged in the layout editor and where it would land, worked out from the
/// frames of everything it can land on.
@Observable
final class LayoutDrag {
    enum Item: Equatable {
        /// A card on the Home tab, as it was when picked up.
        case card(HomeCard)
        /// A widget from the tray, not on the Home tab yet.
        case widget(HomeWidget)
        /// A shown Home column, by its handle.
        case column(Int)
    }

    enum Target: Equatable {
        /// Into column `id`, `index` cards down among the ones staying there.
        case column(id: Int, index: Int)
        /// Off the Home tab, onto the tray.
        case tray
        /// The shown columns in this order.
        case order([Int])
    }

    struct Landing {
        /// Where the lifted copy glides.
        let frame: CGRect
        /// The Home tab to keep once it's there; nil leaves it as it was.
        let layout: HomeLayout?
    }

    private(set) var item: Item?
    private(set) var target: Target?
    /// The column under the pointer, when what's dragged fits there at neither size.
    private(set) var blockedColumn: Int?
    /// The pointer; only the lifted copy follows it, so only that redraws as it moves.
    private(set) var location: CGPoint = .zero
    /// Where the lifted copy glides once let go.
    private(set) var landingFrame: CGRect?
    /// The preview's size over the real notch's.
    var scale: CGFloat = 1

    // Measured as they're laid out, in the editor's coordinate space.
    @ObservationIgnored var cardFrames: [HomeWidget: CGRect] = [:]
    @ObservationIgnored var columnFrames: [Int: CGRect] = [:]
    @ObservationIgnored var chipFrames: [HomeWidget: CGRect] = [:]
    @ObservationIgnored var trayFrame: CGRect = .zero
    @ObservationIgnored var notchFrame: CGRect = .zero

    /// Where the item was when picked up, and the way from the pointer to its middle.
    @ObservationIgnored private(set) var pickupFrame: CGRect = .zero
    @ObservationIgnored private var pickupOffset: CGSize = .zero
    /// How a card looked, or a column's cards and width, to draw the lifted copy.
    @ObservationIgnored private(set) var pickupStyle = HomeCardStyle.large(.full)
    @ObservationIgnored private(set) var pickupColumn: HomeColumn?
    @ObservationIgnored private(set) var pickupColumnWidth: CGFloat = 0
    /// The shown columns' widths, and where the first starts, as a column was picked up.
    @ObservationIgnored private var columnWidths: [Int: CGFloat] = [:]
    @ObservationIgnored private var columnsOrigin: CGFloat = 0

    /// A drag is going on, whether or not it picked anything up.
    @ObservationIgnored private(set) var isTracking = false
    /// The drag going on started on nothing that moves.
    @ObservationIgnored private var isIgnoring = false

    /// The widgets being dragged, which get a slot wherever they'd land.
    var draggedWidgets: Set<HomeWidget> {
        switch item {
        case .card(let card)?: Set(card.widgets)
        case .widget(let widget)?: [widget]
        default: []
        }
    }

    /// While a widget is dragged, empty columns show as slots to drop it in.
    var showsEmptyColumns: Bool {
        switch item {
        case .card?, .widget?: true
        default: false
        }
    }

    var liftedColumn: Int? {
        if case .column(let id)? = item { id } else { nil }
    }

    /// Being let go over the tray.
    var isRemoving: Bool { target == .tray }

    /// The lifted copy: under the pointer where it was picked up, or gliding to land.
    var liftedFrame: CGRect {
        if let landingFrame { return landingFrame }
        var middle = CGPoint(x: location.x + pickupOffset.width, y: location.y + pickupOffset.height)
        // A column only moves sideways.
        if liftedColumn != nil { middle.y = pickupFrame.midY }
        return CGRect(
            x: middle.x - pickupFrame.width / 2, y: middle.y - pickupFrame.height / 2,
            width: pickupFrame.width, height: pickupFrame.height
        )
    }

    /// The Home tab as it would be with what's dragged dropped where it's over, or as it is.
    func displayed(_ layout: HomeLayout) -> HomeLayout {
        switch (item, target) {
        case (.column?, .order(let ids)?):
            var shown = layout
            shown.reorder(shown: ids)
            return shown
        case (.card(let card)?, .tray?):
            var shown = layout
            for widget in card.widgets {
                shown.remove(widget)
            }
            return shown
        case (_, .column(let id, let index)?):
            return placing(in: id, at: index, layout: layout) ?? layout
        default:
            return layout
        }
    }

    // MARK: Picking up, moving and letting go

    /// Picks up what's at `start`: a column by its handle, a card, or a widget on the tray.
    func begin(at start: CGPoint, layout: HomeLayout, showsHome: Bool) {
        isTracking = true
        // A drag that starts while the last one lands is ignored.
        guard landingFrame == nil else {
            isIgnoring = true
            return
        }
        let shown = layout.visibleColumns
        if showsHome, shown.count > 1,
           let column = shown.first(where: { handleFrame(of: $0.id)?.contains(start) == true }),
           let frame = columnFrames[column.id] {
            columnWidths = Dictionary(uniqueKeysWithValues: shown.compactMap { shown in
                columnFrames[shown.id].map { (shown.id, $0.width) }
            })
            columnsOrigin = shown.compactMap { columnFrames[$0.id]?.minX }.min() ?? frame.minX
            pickupColumn = column
            pickupColumnWidth = layout.width(of: column, sharing: HomeTabView.width)
            pickUp(.column(column.id), frame: frame, at: start)
        } else if showsHome, let (column, card) = card(at: start, in: shown), let frame = cardFrames[card.id] {
            pickupStyle = column.style(of: card, width: layout.width(of: column, sharing: HomeTabView.width))
            pickUp(.card(card), frame: frame, at: start)
        } else if let widget = HomeWidget.allCases.first(where: { !layout.contains($0) && chipFrames[$0]?.contains(start) == true }),
                  let frame = chipFrames[widget] {
            pickUp(.widget(widget), frame: frame, at: start)
        } else {
            isIgnoring = true
        }
    }

    /// Follows the pointer and works out where what's dragged would land.
    func move(to point: CGPoint, layout: HomeLayout) {
        guard !isIgnoring, landingFrame == nil, let item else { return }
        location = point
        switch item {
        case .column(let id):
            aim(at: .order(order(moving: id, to: point, layout: layout)), blocked: nil)
        case .card, .widget:
            aimDrop(at: point, layout: layout)
        }
    }

    /// Lets go: where the lifted copy lands and the Home tab to keep, or nil if nothing was
    /// picked up.
    func end(layout: HomeLayout) -> Landing? {
        isTracking = false
        if isIgnoring {
            isIgnoring = false
            return nil
        }
        guard let item, landingFrame == nil else { return nil }
        let result = displayed(layout)
        let frame: CGRect? = switch item {
        // Off the Home tab, it shrinks away where it was let go.
        case .card where target == .tray: liftedFrame.insetBy(dx: liftedFrame.width * 0.3, dy: liftedFrame.height * 0.3)
        // Into its slot, which is back where it was if it landed nowhere.
        case .card(let card): cardFrames[card.id]
        case .widget(let widget): target == nil ? chipFrames[widget] : cardFrames[widget]
        case .column(let id): columnFrames[id]
        }
        return Landing(frame: frame ?? pickupFrame, layout: result == layout ? nil : result)
    }

    func land(at frame: CGRect) {
        landingFrame = frame
    }

    func reset() {
        item = nil
        target = nil
        blockedColumn = nil
        landingFrame = nil
    }

    // MARK: Helpers

    private func pickUp(_ item: Item, frame: CGRect, at point: CGPoint) {
        pickupFrame = frame
        pickupOffset = CGSize(width: frame.midX - point.x, height: frame.midY - point.y)
        location = point
        target = nil
        blockedColumn = nil
        self.item = item
    }

    private func card(at point: CGPoint, in columns: [HomeColumn]) -> (HomeColumn, HomeCard)? {
        for column in columns {
            if let card = column.cards.first(where: { cardFrames[$0.id]?.contains(point) == true }) {
                return (column, card)
            }
        }
        return nil
    }

    /// The strip under a shown column, where its handle is.
    private func handleFrame(of column: Int) -> CGRect? {
        columnFrames[column].map { CGRect(x: $0.minX, y: $0.maxY, width: $0.width, height: ColumnHandle.height * scale) }
    }

    private func aim(at target: Target?, blocked: Int?) {
        if self.target != target { self.target = target }
        if blockedColumn != blocked { blockedColumn = blocked }
    }

    /// Over the tray, a card would come off the Home tab, unless it's the clock; over the notch,
    /// what's dragged would go into the column under the pointer, among its cards where the
    /// pointer is.
    private func aimDrop(at point: CGPoint, layout: HomeLayout) {
        if case .card(let card)? = item, card.isRemovable, trayFrame.insetBy(dx: -6, dy: -6).contains(point) {
            return aim(at: .tray, blocked: nil)
        }
        guard notchFrame.insetBy(dx: -12, dy: -12).contains(point) else {
            return aim(at: nil, blocked: nil)
        }
        // The columns as they're shown now, empty ones as slots.
        let slots = displayed(layout).columns
            .compactMap { column in columnFrames[column.id].map { (column: column, frame: $0) } }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard let first = slots.first, let last = slots.last else { return }
        let slot: (column: HomeColumn, frame: CGRect)
        if let over = slots.first(where: { $0.frame.minX <= point.x && point.x <= $0.frame.maxX }) {
            slot = over
        } else if point.x < first.frame.minX {
            slot = first
        } else if point.x > last.frame.maxX {
            slot = last
        } else {
            // Between two columns: it stays with the one it was over.
            return
        }
        let index = insertionIndex(at: point, in: slot.column)
        if placing(in: slot.column.id, at: index, layout: layout) != nil {
            aim(at: .column(id: slot.column.id, index: index), blocked: nil)
        } else {
            aim(at: nil, blocked: slot.column.id)
        }
    }

    /// How many of the cards staying in `column` come before `point`: those above it, and
    /// those beside each other on its row that it's past the middle of.
    private func insertionIndex(at point: CGPoint, in column: HomeColumn) -> Int {
        let dragged = draggedWidgets
        let rows = column.rows
        var index = 0
        for card in column.cards where !card.widgets.allSatisfy(dragged.contains) {
            guard let frame = cardFrames[card.id] else { continue }
            let isBeside = (rows.first { $0.contains(card) }?.count ?? 1) > 1
            let isBefore = point.y >= frame.maxY
                || (point.y >= frame.minY && (isBeside ? point.x > frame.midX : point.y > frame.midY))
            guard isBefore else { break }
            index += 1
        }
        return index
    }

    /// The Home tab with what's dragged in column `id` at `index`, if it fits there: a card at
    /// its size or else the other, a new widget small (on its own it still shows large).
    private func placing(in id: Int, at index: Int, layout: HomeLayout) -> HomeLayout? {
        switch item {
        case .card(let card)?: layout.dropping(card.widgets, large: card.isLarge, in: id, at: index)
        case .widget(let widget)?: layout.dropping([widget], large: false, in: id, at: index)
        default: nil
        }
    }

    /// The shown columns, with `id` moved past each neighbour whose middle the lifted copy's
    /// middle has passed.
    private func order(moving id: Int, to point: CGPoint, layout: HomeLayout) -> [Int] {
        var order = if case .order(let current)? = target { current } else { layout.visibleColumns.map(\.id) }
        let spacing = HomeLayout.columnSpacing * scale
        func middle(of column: Int, in order: [Int]) -> CGFloat {
            columnsOrigin
                + order.prefix { $0 != column }.reduce(0) { $0 + (columnWidths[$1] ?? 0) + spacing }
                + (columnWidths[column] ?? 0) / 2
        }
        let lifted = point.x + pickupOffset.width
        while let index = order.firstIndex(of: id) {
            if index + 1 < order.count, lifted > middle(of: order[index + 1], in: order) {
                order.swapAt(index, index + 1)
            } else if index > 0, lifted < middle(of: order[index - 1], in: order) {
                order.swapAt(index, index - 1)
            } else {
                break
            }
        }
        return order
    }
}

// MARK: - Preview

/// The open notch with the tab picked; the Home tab as it would be with the drag dropped where
/// it is.
private struct NotchPreview: View {
    @Environment(AppServices.self) private var services
    @Environment(LayoutDrag.self) private var drag
    @Binding var shownTab: NotchTab

    var body: some View {
        let settings = services.settings
        let notch = services.notch.primary?.geometry.notchSize
            ?? CGSize(width: NotchGeometry.virtualNotchWidth, height: 32)
        let size = CGSize(width: NotchMetrics.openWidth, height: notch.height + NotchMetrics.openContentHeight)
        let ears = NotchMetrics.maxTopRadius
        let tabs = settings.visibleTabs
        let tab = tabs.contains(shownTab) ? shownTab : tabs[0]

        ScaledToFit(size: CGSize(width: size.width + ears * 2, height: size.height)) {
            VStack(spacing: 0) {
                WingsLayout(notch: notch) {
                    // Like the real tab bar, a lone tab shows nothing.
                    if tabs.count > 1 {
                        ReorderableStack(items: tabOrder, spacing: 4) { item in
                            NotchTabIcon(tab: item, isSelected: item == tab)
                                .help(item.title)
                                .onTapGesture { shownTab = item }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { shownTab = item }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 18)
                    } else {
                        Color.clear
                    }
                } trailing: {
                    HeaderStatusView()
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 18)
                }

                Group {
                    if tab == .home {
                        HomeColumnsPreview()
                    } else {
                        TabPlaceholder(tab: tab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .transition(.blurReplace)
                .id(tab)
            }
            .frame(width: size.width, height: size.height)
            .frame(width: size.width + ears * 2)
            .background(NotchShape(topRadius: ears, bottomRadius: 32).fill(.black))
            .animation(.notchQuick, value: tab)
        } onScale: { scale in
            drag.scale = scale
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchLayoutEditor.space)) } action: { frame in
            drag.notchFrame = frame
        }
        .environment(\.colorScheme, .dark)
    }

    /// The shown tabs in order; rearranging them leaves the hidden ones where they are.
    private var tabOrder: Binding<[NotchTab]> {
        let settings = services.settings
        return Binding {
            settings.visibleTabs
        } set: {
            settings.tabOrder = LayoutOrder.rearranged(settings.tabOrder, shown: $0)
        }
    }
}

/// The Home columns as they'd be with the drag dropped where it is. While a widget is dragged,
/// empty columns show as slots to start a column in.
private struct HomeColumnsPreview: View {
    @Environment(AppServices.self) private var services
    @Environment(LayoutDrag.self) private var drag

    var body: some View {
        let shown = drag.displayed(services.settings.homeLayout)
        let showsSlots = drag.showsEmptyColumns
        let columns = showsSlots ? shown.columns : shown.visibleColumns
        Group {
            if columns.isEmpty {
                VStack(spacing: 6) {
                    Text("No Home widgets")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Drag some here from below")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: HomeLayout.columnSpacing) {
                    ForEach(columns) { column in
                        if column.isEmpty {
                            EmptyColumnSlot(id: column.id)
                        } else {
                            EditorColumn(
                                column: column,
                                width: shown.width(of: column, sharing: HomeTabView.width),
                                canMove: shown.visibleColumns.count > 1
                            )
                            .frame(width: shown.fixedWidth(of: column))
                        }
                    }
                }
            }
        }
        .animation(.notchQuick, value: shown)
        .animation(.notchQuick, value: showsSlots)
    }
}

/// A Home column laid out like the real one, with a slot where a dragged widget would land
/// and a handle under it to drag the column by. Right-click a card to resize, move or remove it.
private struct EditorColumn: View {
    @Environment(AppServices.self) private var services
    @Environment(LayoutDrag.self) private var drag
    let column: HomeColumn
    let width: CGFloat
    /// There are other columns to move it past.
    let canMove: Bool

    var body: some View {
        let settings = services.settings
        let dragged = drag.draggedWidgets
        HomeColumnStack(column: column, width: width) { card, style in
            Group {
                if !dragged.isEmpty, card.widgets.allSatisfy(dragged.contains) {
                    CardSlot(card: card, style: style)
                } else {
                    EditorCard(card: card, style: style, isJoined: card.widgets.contains(where: dragged.contains))
                        .contextMenu { PreviewCardMenu(card: card, column: column, settings: settings) }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchLayoutEditor.space)) } action: { frame in
                drag.cardFrames[card.id] = frame
            }
        }
        .overlay {
            if drag.blockedColumn == column.id {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(.red.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(-3)
            }
        }
        .overlay(alignment: .bottom) {
            // In the margin under the column.
            if canMove, drag.item == nil || drag.liftedColumn != nil {
                ColumnHandle()
                    .offset(y: ColumnHandle.height)
            }
        }
        .opacity(drag.liftedColumn == column.id ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchLayoutEditor.space)) } action: { frame in
            drag.columnFrames[column.id] = frame
        }
        // Only the column's own changes; the preview moves columns around by itself.
        .animation(.notchQuick, value: column)
        .accessibilityActions {
            Button("Move Column Left") { settings.homeLayout.moveColumn(column.id, by: -1) }
            Button("Move Column Right") { settings.homeLayout.moveColumn(column.id, by: 1) }
        }
    }
}

/// A Home card: its widget's icon and name on glass.
private struct EditorCard: View {
    let card: HomeCard
    let style: HomeCardStyle
    /// A dragged widget would share this card.
    var isJoined = false
    @State private var isHovered = false

    var body: some View {
        let isRow = if case .small = style { true } else { false }
        // Only the icon fits.
        let isNarrow = style == .small(isNarrow: true)
        let layout = isRow ? AnyLayout(HStackLayout(spacing: 7)) : AnyLayout(VStackLayout(spacing: 9))
        GlassCard(padding: 10) {
            layout {
                HStack(spacing: 4) {
                    ForEach(card.widgets) { widget in
                        WidgetIcon(widget: widget, size: isRow ? 22 : 32)
                    }
                }
                if !isNarrow {
                    Text(card.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity, minHeight: isRow ? 26 : nil, maxHeight: .infinity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(isJoined ? 0.85 : isHovered ? 0.3 : 0), lineWidth: isJoined ? 2 : 1)
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .pointerStyle(.grabIdle)
        .help(isNarrow ? card.title : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.title)
    }
}

/// Where a dragged widget would land: a dashed outline in its color.
private struct CardSlot: View {
    let card: HomeCard
    let style: HomeCardStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let isRow = if case .small = style { true } else { false }
        shape
            .fill(card.tint.opacity(0.16))
            .overlay(shape.strokeBorder(card.tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            // A small card's height, which it keeps beside a large one.
            .frame(maxWidth: .infinity, minHeight: isRow ? 46 : nil, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// An empty column while a widget is dragged: a slot to drop it in, which starts a column there.
private struct EmptyColumnSlot: View {
    @Environment(LayoutDrag.self) private var drag
    let id: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: 44)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchLayoutEditor.space)) } action: { frame in
                drag.columnFrames[id] = frame
            }
            .transition(.opacity.combined(with: .scale(0.9)))
            .accessibilityHidden(true)
    }
}

/// The grip under a column to drag it sideways by.
private struct ColumnHandle: View {
    /// The notch's margin under the columns, which it fills.
    static let height: CGFloat = 14
    @State private var isHovered = false

    var body: some View {
        Capsule()
            .fill(.white.opacity(isHovered ? 0.6 : 0.22))
            .frame(width: isHovered ? 36 : 28, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .animation(.notchQuick, value: isHovered)
            .pointerStyle(.grabIdle)
            .help("Drag to move the column")
            .accessibilityHidden(true)
    }
}

/// A widget's symbol on a rounded square of its color, like the icons in Settings' sidebar.
private struct WidgetIcon: View {
    let widget: HomeWidget
    let size: CGFloat

    var body: some View {
        Image(systemName: widget.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(widget.tint.gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The copy of what's dragged that follows the pointer, raised a little with a shadow, and
/// glides to where it lands once let go.
private struct LiftedItem: View {
    @Environment(LayoutDrag.self) private var drag

    var body: some View {
        if let item = drag.item {
            let frame = drag.liftedFrame
            let isLanding = drag.landingFrame != nil
            let isBlocked = drag.blockedColumn != nil && !isLanding
            Group {
                switch item {
                case .card(let card):
                    scaled(EditorCard(card: card, style: drag.pickupStyle), to: frame)
                case .column:
                    if let column = drag.pickupColumn {
                        scaled(
                            HomeColumnStack(column: column, width: drag.pickupColumnWidth) { card, style in
                                EditorCard(card: card, style: style)
                            },
                            to: frame
                        )
                    }
                case .widget(let widget):
                    TrayChip(widget: widget, isLifted: true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isBlocked {
                    Image(systemName: "nosign")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.red, in: .circle)
                        .offset(x: 6, y: -6)
                }
            }
            // Over the tray it shrinks, out of the way of what the tray says.
            .scaleEffect(isLanding ? 1 : drag.isRemoving ? 0.6 : 1.04)
            .animation(.notchQuick, value: drag.isRemoving)
            .shadow(color: .black.opacity(isLanding ? 0 : 0.3), radius: 10, y: 6)
            .opacity(isLanding && drag.isRemoving ? 0 : 1)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
        }
    }

    /// Notch content drawn at the real notch's size, scaled down like the preview, on black so
    /// what it passes over doesn't show through its glass.
    private func scaled(_ content: some View, to frame: CGRect) -> some View {
        let scale = max(drag.scale, 0.01)
        return content
            .background(.black, in: .rect(cornerRadius: 20, style: .continuous))
            .frame(width: frame.width / scale, height: frame.height / scale)
            .scaleEffect(scale)
            .frame(width: frame.width, height: frame.height)
            .environment(\.colorScheme, .dark)
    }
}

/// A card's right-click menu in the preview: the size of each widget it shows, removing it,
/// and moving it in its column or its column along the notch.
private struct PreviewCardMenu: View {
    let card: HomeCard
    let column: HomeColumn
    let settings: AppSettings

    var body: some View {
        let layout = settings.homeLayout
        ForEach(card.widgets) { widget in
            Section(widget.title) {
                SizeToggles(widgets: [widget], isLarge: card.isLarge, settings: settings)
                if widget.isRemovable {
                    Button("Remove") { settings.homeLayout.remove(widget) }
                }
            }
        }
        if column.cards.count > 1 {
            Divider()
            CardMoveButtons(card: card, column: column, settings: settings)
        }
        let shown = layout.visibleColumns.map(\.id)
        Divider()
        Button("Move Column Left") { settings.homeLayout.moveColumn(column.id, by: -1) }
            .disabled(shown.first == column.id)
        Button("Move Column Right") { settings.homeLayout.moveColumn(column.id, by: 1) }
            .disabled(shown.last == column.id)
    }
}

/// Another tab in the preview: one card saying what it holds.
private struct TabPlaceholder: View {
    let tab: NotchTab

    var body: some View {
        GlassCard(padding: 10) {
            VStack(spacing: 8) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(tab.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension NotchTab {
    var summary: String {
        switch self {
        case .home: String(localized: "Now Playing, the clock, weather and your agenda")
        case .shelf: String(localized: "Files you drop on the notch")
        case .timers: String(localized: "Timer, stopwatch and Pomodoro")
        case .camera: String(localized: "A quick look at your camera")
        }
    }
}

/// Lays `content` out at `size` and scales it down to the width on offer, telling `onScale`
/// by how much.
private struct ScaledToFit<Content: View>: View {
    let size: CGSize
    @ViewBuilder var content: Content
    var onScale: (CGFloat) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, proxy.size.width / size.width)
            content
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .onChange(of: scale, initial: true) { onScale(scale) }
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: size.width)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tray

/// Under the notch: the widgets that aren't on the Home tab, to drag onto it, and the place to
/// drop one from it to take it off. The clock, which stays, isn't taken.
private struct WidgetTray: View {
    @Environment(AppServices.self) private var services
    @Environment(LayoutDrag.self) private var drag

    var body: some View {
        let layout = services.settings.homeLayout
        let widgets = HomeWidget.allCases.filter { !layout.contains($0) }
        let lifted: HomeCard? = if case .card(let card)? = drag.item, drag.landingFrame == nil { card } else { nil }
        let isTakingOff = lifted != nil
        let isOver = drag.target == .tray && isTakingOff
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        FlowLayout(spacing: 6) {
            ForEach(widgets) { widget in
                TrayChip(widget: widget)
                    .opacity(drag.item == .widget(widget) ? 0.35 : 1)
                    .pointerStyle(.grabIdle)
                    .help("Drag onto the notch to add \(widget.title)")
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchLayoutEditor.space)) } action: { frame in
                        drag.chipFrames[widget] = frame
                    }
                    .accessibilityAction(named: "Add to Home") { add(widget) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        // Kept in place under the message, so the tray doesn't change size.
        .opacity(isTakingOff ? 0 : 1)
        .overlay {
            if let lifted, !lifted.isRemovable {
                Label("\(lifted.title) stays on the Home tab", systemImage: "lock")
                    .foregroundStyle(.secondary)
            } else if isTakingOff {
                Label(
                    isOver ? "Release to take it off the Home tab" : "Drop here to take it off the Home tab",
                    systemImage: isOver ? "minus.circle.fill" : "minus.circle"
                )
                .foregroundStyle(isOver ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            } else if widgets.isEmpty {
                Text("Every widget is on the Home tab. Drag one here to take it off.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(8)
        .background(isOver ? AnyShapeStyle(.red.opacity(0.12)) : AnyShapeStyle(.fill.quaternary), in: shape)
        .overlay {
            shape.strokeBorder(
                isOver ? AnyShapeStyle(.red.opacity(0.6)) : AnyShapeStyle(.separator),
                style: StrokeStyle(lineWidth: 1, dash: lifted?.isRemovable == true ? [5, 3] : [])
            )
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchLayoutEditor.space)) } action: { frame in
            drag.trayFrame = frame
        }
        .animation(.notchQuick, value: isTakingOff)
        .animation(.notchQuick, value: isOver)
    }

    /// Puts `widget` small at the bottom of the first column with room for it.
    private func add(_ widget: HomeWidget) {
        let layout = services.settings.homeLayout
        for column in layout.visibleColumns + layout.columns.filter(\.isEmpty) {
            if let added = layout.dropping([widget], large: false, in: column.id, at: column.cards.count) {
                services.settings.homeLayout = added
                return
            }
        }
    }
}

/// A widget on the tray, to drag onto the notch.
private struct TrayChip: View {
    let widget: HomeWidget
    /// Following the pointer, over whatever's under it.
    var isLifted = false

    var body: some View {
        HStack(spacing: 6) {
            WidgetIcon(widget: widget, size: 18)
            Text(widget.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(isLifted ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.background), in: .capsule)
        .overlay(Capsule().strokeBorder(.separator))
        .fixedSize()
    }
}

/// Lays its subviews out left to right, starting another row when one is full.
private nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Colors

extension HomeWidget {
    /// What the layout editor colors it with.
    var tint: Color {
        switch self {
        case .media: .pink
        case .clock: .purple
        case .weather: .cyan
        case .calendar: .red
        case .reminders: .blue
        case .battery: .green
        case .timer: .orange
        }
    }
}

extension HomeCard {
    var tint: Color { id.tint }
}
