import QuickLookThumbnailing
import SwiftUI

enum ShelfMetrics {
    static let itemWidth: CGFloat = 84
    static let spacing: CGFloat = 4
    /// The room an item takes in the row: the gap that opens where a drop would land.
    static let slot = itemWidth + spacing
}

/// The Shelf tab: parked files, handled the way Finder handles them (see `ShelfController`).
/// Drag them out, along the row to reorder them, onto AirDrop or Share to send them, or onto
/// Remove (Clear until then) to take them off; files dropped on the row land where it opens a gap.
struct ShelfTabView: View {
    @State private var shelf: ShelfController

    init(model: NotchViewModel) {
        _shelf = State(initialValue: ShelfController(model: model))
    }

    var body: some View {
        HStack(spacing: 10) {
            ShelfCard(shelf: shelf)
            ShelfActions(shelf: shelf)
                .frame(width: 96)
        }
        .overlay {
            if shelf.isConfirmingClear {
                ClearConfirmation(shelf: shelf)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .coordinateSpace(.named(ShelfController.space))
        .background(ShelfAnchor(shelf: shelf))
        .onAppear { shelf.start() }
        .onDisappear { shelf.stop() }
    }
}

/// The glass card with the row of items, or a hint while the shelf is empty. A click on it
/// outside the items deselects them.
private struct ShelfCard: View {
    @Environment(AppServices.self) private var services
    let shelf: ShelfController
    @State private var isTargeted = false

    var body: some View {
        let isEmpty = services.shelf.items.isEmpty
        GlassCard(padding: isEmpty ? 10 : 0, tint: isTargeted ? .accentColor : nil) {
            if isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.5))
                        .bounces(whenTargeted: isTargeted)
                    Text("Drop files here to keep them handy")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Drag them out anywhere later, or send them with AirDrop.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ShelfRow(shelf: shelf)
            }
        }
        .contentShape(.rect)
        .onTapGesture { shelf.clickBackground() }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShelfController.space)) } action: { shelf.cardFrame = $0 }
        .onDrop(of: ShelfStore.acceptedTypes, delegate: ShelfDropDelegate(shelf: shelf, isTargeted: $isTargeted))
    }
}

/// The items side by side, scrolling sideways when they don't fit. Dragging some of them carries
/// the selection along when they're part of it.
private struct ShelfRow: View {
    @Environment(AppServices.self) private var services
    let shelf: ShelfController
    @State private var width: CGFloat = 0

    var body: some View {
        let store = services.shelf
        let items = shelf.rowItems
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: ShelfMetrics.spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if let url = store.url(for: item) {
                            ShelfItemView(item: item, url: url, shelf: shelf)
                                .padding(.leading, shelf.gapIndex == index ? ShelfMetrics.slot : 0)
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(ShelfController.space)).minX } action: {
                    shelf.rowLeading = $0
                }
                .padding(.trailing, shelf.gapIndex == items.count ? ShelfMetrics.slot : 0)
                .padding(.horizontal, 10)
                .frame(minWidth: width, maxHeight: .infinity, alignment: .leading)
                .dragContainer(for: ShelfFile.self) { ids in shelf.files(for: ids) }
                .dragContainerSelection(shelf.selection.ordered(shelf.order))
                .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: true, allowMove: true)))
                .onDragSessionUpdated { shelf.dragSessionUpdated($0) }
            }
            .scrollIndicators(.never)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShelfController.space)) } action: { frame in
                width = frame.width
                shelf.rowFrame = frame
            }
            // Keep the item the arrow keys moved to in view, and what was just added.
            .onChange(of: shelf.selection.cursor) { _, cursor in
                guard let cursor else { return }
                withAnimation(.notchQuick) { proxy.scrollTo(cursor) }
            }
            .onAppear {
                if let cursor = shelf.selection.cursor { proxy.scrollTo(cursor) }
            }
        }
        .animation(.notchQuick, value: store.items.map(\.id))
    }
}

/// An item as Finder shows one in icon view: when selected, its icon sits on a gray rounded
/// square and its name on the accent color.
private struct ShelfItemView: View {
    let item: ShelfItem
    let url: URL
    let shelf: ShelfController
    @State private var thumbnail: NSImage?

    var body: some View {
        let isSelected = shelf.selection.contains(item.id)
        VStack(spacing: 3) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .padding(5)
                .background(.white.opacity(isSelected ? 0.16 : 0), in: .rect(cornerRadius: 8))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShelfController.space)) } action: {
                    shelf.iconFrames[item.id] = $0
                }
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: .rect(cornerRadius: 4))
                .frame(maxWidth: ShelfMetrics.itemWidth)
        }
        .frame(width: ShelfMetrics.itemWidth)
        // Dragged over the card it leaves its slot empty, following the icon unseen; dropped
        // there, it shows up in its new slot as the drag ends, where its drag image slid.
        // Dragged anywhere else it stays dimmed in place.
        .animation(shelf.draggedIDs.isEmpty ? nil : .notchQuick) {
            $0.opacity(shelf.isLifted(item.id) ? 0 : shelf.draggedIDs.contains(item.id) ? 0.4 : 1)
        }
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture { shelf.click(item.id, event: NSApp.currentEvent) }
        .draggable(containerItemID: item.id)
        .contextMenu { ShelfItemMenu(item: item, shelf: shelf) }
        .offset(x: shelf.isLifted(item.id) ? shelf.iconOffset : 0)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShelfController.space)) } action: {
            shelf.itemFrames[item.id] = $0
        }
        .help(url.path)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction { shelf.click(item.id, event: nil) }
        .accessibilityAction(named: "Open") { shelf.open([item.id]) }
        .accessibilityAction(named: "Quick Look") { shelf.quickLook([item.id]) }
        .task(id: url) {
            let size = CGSize(width: 104, height: 104)
            let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
            let image: NSImage
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = representation.nsImage
            } else {
                // Folders, apps and archives have no thumbnail, only their icon. Drawn as it is,
                // the icon comes out darker in the drag image than in the row, so a folder seemed
                // to open as it was picked up and close as it landed. A bitmap of it can't.
                image = NSWorkspace.shared.icon(forFile: url.path).bitmap(size: size, scale: 2)
            }
            thumbnail = image
            shelf.thumbnails[item.id] = image
        }
    }
}

private extension NSImage {
    /// The image drawn once into a bitmap of `size` points, in the notch's dark appearance.
    func bitmap(size: CGSize, scale: CGFloat) -> NSImage {
        var rect = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        var image: CGImage?
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            image = cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return image.map { NSImage(cgImage: $0, size: size) } ?? self
    }
}

/// An item's right-click menu. It acts on the whole selection when the item is part of it.
private struct ShelfItemMenu: View {
    let item: ShelfItem
    let shelf: ShelfController

    var body: some View {
        let targets = shelf.targets(for: item.id)
        let count = targets.count
        Button(count > 1 ? "Open \(count) Items" : "Open") { shelf.open(targets) }
            .keyboardShortcut("o")
        Button(count > 1 ? "Quick Look \(count) Items" : "Quick Look") { shelf.quickLook(targets) }
            .keyboardShortcut(.space, modifiers: [])
        Divider()
        Button("AirDrop") { shelf.airDrop(targets) }
        Button("Share…") { shelf.share(targets, from: item.id) }
        Button("Show in Finder") { shelf.showInFinder(targets) }
        Button(count > 1 ? "Copy \(count) Items" : "Copy") { shelf.copy(targets) }
            .keyboardShortcut("c")
        Divider()
        Button(count > 1 ? "Remove \(count) Items from Shelf" : "Remove from Shelf", role: .destructive) { shelf.remove(targets) }
            .keyboardShortcut(.delete)
    }
}

/// AirDrop, Share and Clear beside the card. AirDrop and Share act on the selection, or on
/// everything when nothing is selected; files dropped on AirDrop are sent straight away, files
/// dropped on Share get the share picker. While the shelf's own items are dragged, Clear becomes
/// Remove: items dropped on it leave the shelf.
private struct ShelfActions: View {
    @Environment(AppServices.self) private var services
    let shelf: ShelfController
    @State private var isAirDropTargeted = false
    @State private var isShareTargeted = false
    @State private var isClearTargeted = false

    var body: some View {
        let isEmpty = services.shelf.items.isEmpty
        VStack(spacing: 8) {
            SideAction(title: "AirDrop", symbol: "dot.radiowaves.up.forward", disabled: isEmpty, isTargeted: isAirDropTargeted) {
                shelf.airDrop(shelf.selectedOrAll)
            }
            .onDrop(of: ShelfStore.acceptedTypes, isTargeted: $isAirDropTargeted) { shelf.airDropDrop($0) }
            .help(shelf.selection.isEmpty ? "Send everything on the Shelf with AirDrop" : "Send the selected items with AirDrop")
            SideAction(title: "Share", symbol: "square.and.arrow.up", disabled: isEmpty, isTargeted: isShareTargeted) {
                shelf.shareFromButton()
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShelfController.space)) } action: {
                shelf.shareButtonFrame = $0
            }
            .onDrop(of: ShelfStore.acceptedTypes, isTargeted: $isShareTargeted) { shelf.shareDrop($0) }
            .help(shelf.selection.isEmpty ? "Share everything on the Shelf" : "Share the selected items")
            SideAction(
                title: shelf.draggedIDs.isEmpty ? "Clear" : "Remove", symbol: "trash", disabled: isEmpty,
                isTargeted: isClearTargeted, targetTint: .red
            ) {
                shelf.askToClear()
            }
            .onDrop(of: ShelfStore.acceptedTypes, delegate: ClearDropDelegate(shelf: shelf, isTargeted: $isClearTargeted))
            .help("Remove everything from the Shelf, or the items dropped on it")
        }
    }
}

private struct SideAction: View {
    let title: LocalizedStringKey
    let symbol: String
    let disabled: Bool
    /// Files are dragged over it.
    var isTargeted = false
    /// The glass's tint while files are dragged over it.
    var targetTint = Color.accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .bounces(whenTargeted: isTargeted)
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled && !isTargeted ? .white.opacity(0.3) : .white)
        .glassEffect(
            isTargeted ? .regular.tint(targetTint.opacity(0.5)).interactive() : disabled ? .regular : .regular.interactive(),
            in: .rect(cornerRadius: 18)
        )
        .disabled(disabled)
    }
}

/// Asks before Clear empties the shelf: a card over the dimmed tab. Return clears; Escape or a
/// click beside the card cancels.
private struct ClearConfirmation: View {
    @Environment(AppServices.self) private var services
    let shelf: ShelfController

    var body: some View {
        let items = services.shelf.items
        ZStack {
            Color.black.opacity(0.6)
                .contentShape(.rect)
                .onTapGesture { shelf.cancelClear() }
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Clear the Shelf?")
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: Self.message(for: items))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button { shelf.cancelClear() } label: {
                        Text("Cancel").frame(minWidth: 60)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    Button { shelf.confirmClear() } label: {
                        Text("Clear").frame(minWidth: 60)
                    }
                    .buttonStyle(.tintedGlass(.red))
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: 290)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    static func message(for items: [ShelfItem]) -> String {
        let removed = items.count == 1
            ? String(localized: "This removes the item from the Shelf.")
            : String(localized: "This removes all \(items.count) items from the Shelf.")
        let files = items.contains(where: \.isOwnedCopy)
            ? String(localized: "Images and text dropped on it are deleted; other files stay where they are.")
            : String(localized: "The files themselves stay where they are.")
        return "\(removed) \(files)"
    }
}

/// Drops on the card land where the row opens a gap: this shelf's own items move there, and
/// anything else is added there.
private struct ShelfDropDelegate: DropDelegate {
    let shelf: ShelfController
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = shelf.draggedIDs.isEmpty
        shelf.dragEntered(at: info.location.x)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        shelf.dragMoved(to: info.location.x)
        return DropProposal(operation: shelf.draggedIDs.isEmpty ? .copy : .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        shelf.dragExited()
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        return shelf.drop(info.itemProviders(for: ShelfStore.acceptedTypes), at: info.location.x)
    }
}

/// Only this shelf's own items can be dropped on Clear: they leave the shelf, as ⌫ removes them.
private struct ClearDropDelegate: DropDelegate {
    let shelf: ShelfController
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        !shelf.draggedIDs.isEmpty
    }

    func dropEntered(info: DropInfo) {
        isTargeted = !shelf.draggedIDs.isEmpty
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: shelf.draggedIDs.isEmpty ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        return shelf.clearDrop()
    }
}

/// An AppKit view behind the Shelf tab, in its coordinate space (flipped, like SwiftUI's): the
/// share picker points at frames in it, and Quick Look zooms out of them.
private struct ShelfAnchor: NSViewRepresentable {
    let shelf: ShelfController

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        shelf.anchorView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        shelf.anchorView = view
    }

    private final class AnchorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Shown while a file is dragged near the notch: two glass drop zones.
struct DropTargetView: View {
    @Environment(AppServices.self) private var services
    let model: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            HStack(spacing: 10) {
                // With the Shelf tab hidden there'd be nowhere to see what was dropped.
                if services.settings.visibleTabs.contains(.shelf) {
                    DropTile(title: "Shelf", symbol: "tray.and.arrow.down.fill") { providers in
                        Task {
                            await services.shelf.add(providers: providers)
                            services.drag.endDrag()
                            model.open(tab: .shelf)
                        }
                    }
                }
                DropTile(title: "AirDrop", symbol: "dot.radiowaves.up.forward") { providers in
                    Task {
                        services.drag.endDrag()
                        await AirDropService.send(providers: providers, store: services.shelf)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

private struct DropTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let onDrop: ([NSItemProvider]) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .bounces(whenTargeted: isTargeted)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(isTargeted ? .white : .white.opacity(0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(
            isTargeted ? .regular.tint(.accentColor.opacity(0.5)).interactive() : .regular,
            in: .rect(cornerRadius: 20)
        )
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(.notchQuick, value: isTargeted)
        .onDrop(of: ShelfStore.acceptedTypes, isTargeted: $isTargeted) { providers in
            onDrop(providers)
            return true
        }
    }
}

private extension View {
    /// Bounces the symbol as files are dragged onto it, and not again as they leave.
    func bounces(whenTargeted isTargeted: Bool) -> some View {
        modifier(TargetBounce(isTargeted: isTargeted))
    }
}

private struct TargetBounce: ViewModifier {
    let isTargeted: Bool
    @State private var bounces = 0

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce, value: bounces)
            .onChange(of: isTargeted) { _, targeted in
                if targeted { bounces += 1 }
            }
    }
}
