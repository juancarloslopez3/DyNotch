import SwiftUI

extension EnvironmentValues {
    /// True in the lifted copy a `ReorderableStack` drags around, so an item can leave out what
    /// must be drawn only once, such as a `matchedGeometryEffect`.
    @Entry var isReorderCopy = false
}

/// A row (or column) whose items can be dragged along it to reorder them; the others make way.
/// While dragging, the item's slot stays empty and a lifted copy follows the pointer.
struct ReorderableStack<Item: Hashable, Content: View>: View {
    @Binding var items: [Item]
    var axis: Axis = .horizontal
    let spacing: CGFloat
    /// Move Left and Move Right (Up and Down in a column) in each item's right-click menu, for
    /// items without their own.
    var hasMoveMenu = true
    @ViewBuilder var content: (Item) -> Content

    private struct Drag {
        var item: Item
        /// The copy's leading (or top) edge when the drag began, and now.
        var start: CGFloat
        var edge: CGFloat
        var isLifted = true
    }

    @State private var sizes: [Item: CGSize] = [:]
    @State private var drag: Drag?
    /// Resets by itself when a drag ends or is cancelled; `onEnded` only sees the former.
    @GestureState private var isDragging = false

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
        layout {
            ForEach(items, id: \.self) { item in
                moveMenu(for: item) {
                    content(item)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes[item] = $0 }
                        .opacity(drag?.item == item ? 0 : 1)
                        .accessibilityElement(children: .combine)
                }
                .accessibilityAction(named: moveNames.back) { move(item, by: -1) }
                .accessibilityAction(named: moveNames.forward) { move(item, by: 1) }
            }
        }
        // Only the items in the stack glide; the copy sticks to the pointer.
        .animation(.notchQuick, value: items)
        .overlay(alignment: axis == .horizontal ? .leading : .top) {
            if let drag {
                content(drag.item)
                    .environment(\.isReorderCopy, true)
                    .frame(width: sizes[drag.item]?.width, height: sizes[drag.item]?.height)
                    .scaleEffect(drag.isLifted ? 1.08 : 1)
                    .offset(axis == .horizontal ? CGSize(width: drag.edge, height: 0) : CGSize(width: 0, height: drag.edge))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(.rect)
        .gesture(dragGesture)
        .onChange(of: isDragging) { _, dragging in
            if !dragging { settle() }
        }
        .pointerStyle(drag == nil ? .grabIdle : .grabActive)
    }

    private var moveNames: (back: LocalizedStringKey, forward: LocalizedStringKey) {
        axis == .horizontal ? ("Move Left", "Move Right") : ("Move Up", "Move Down")
    }

    @ViewBuilder
    private func moveMenu(for item: Item, @ViewBuilder _ view: () -> some View) -> some View {
        if hasMoveMenu {
            view().contextMenu {
                Button(moveNames.back) { move(item, by: -1) }
                    .disabled(items.first == item)
                Button(moveNames.forward) { move(item, by: 1) }
                    .disabled(items.last == item)
            }
        } else {
            view()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if drag == nil {
                    let start = along(value.startLocation)
                    guard let item = items.first(where: {
                        let edge = leadingEdge(of: $0, in: items)
                        return start >= edge && start < edge + length($0)
                    }) else { return }
                    let edge = leadingEdge(of: item, in: items)
                    drag = Drag(item: item, start: edge, edge: edge)
                }
                // A drag that starts while the last one settles is ignored.
                guard var current = drag, current.isLifted else { return }
                current.edge = current.start + along(value.translation)

                // Pass a neighbour once the dragged item's middle crosses the neighbour's.
                let middle = current.edge + length(current.item) / 2
                var order = items
                while let index = order.firstIndex(of: current.item) {
                    if index + 1 < order.count, middle > self.middle(of: order[index + 1], in: order) {
                        order.swapAt(index, index + 1)
                    } else if index > 0, middle < self.middle(of: order[index - 1], in: order) {
                        order.swapAt(index, index - 1)
                    } else {
                        break
                    }
                }
                if order != items { items = order }
                drag = current
            }
    }

    /// Glides the lifted copy into its slot, then shows the real item there again.
    private func settle() {
        guard let current = drag, current.isLifted else { return }
        withAnimation(.notchQuick) {
            drag?.edge = leadingEdge(of: current.item, in: items)
            drag?.isLifted = false
        } completion: {
            drag = nil
        }
    }

    private func move(_ item: Item, by step: Int) {
        let order = LayoutOrder.moved(item, by: step, in: items)
        if order != items { items = order }
    }

    private func along(_ point: CGPoint) -> CGFloat { axis == .horizontal ? point.x : point.y }
    private func along(_ size: CGSize) -> CGFloat { axis == .horizontal ? size.width : size.height }

    private func length(_ item: Item) -> CGFloat { sizes[item].map(along) ?? 0 }

    /// Where `item`'s leading (or top) edge sits with the items in `order`.
    private func leadingEdge(of item: Item, in order: [Item]) -> CGFloat {
        order.prefix { $0 != item }.reduce(0) { $0 + length($1) + spacing }
    }

    private func middle(of item: Item, in order: [Item]) -> CGFloat {
        leadingEdge(of: item, in: order) + length(item) / 2
    }
}
