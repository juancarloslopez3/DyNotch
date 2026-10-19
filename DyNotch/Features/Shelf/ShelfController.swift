import AppKit
import Observation
import QuickLookUI
import SwiftUI

/// The Shelf tab's selection, keys and commands, the way Finder does them: click to select (⌘ and
/// ⇧ to add), double-click to open, Space for Quick Look (hold it to peek), ⌘C to copy, ⌫ to
/// remove, arrows and typing to move. Clicking the Shelf hands it the keyboard without making
/// DyNotch the active app; the notch gives it back when it closes.
@Observable
final class ShelfController {
    /// The Shelf tab's coordinate space. Item and button frames are measured in it, and the
    /// anchor view behind the tab has the same one.
    nonisolated static let space = "ShelfTabView"
    /// Holding Space at least this long makes Quick Look a peek that closes when Space is let go.
    static let peekDelay: TimeInterval = 0.5

    let model: NotchViewModel
    private(set) var selection = ShelfSelection()
    /// The Clear button is asking for confirmation.
    private(set) var isConfirmingClear = false
    /// This shelf's items being dragged, and moved if dropped back on the shelf. Over the card
    /// they leave an empty slot where they'd land; anywhere else they're dimmed in place.
    private(set) var draggedIDs: Set<UUID> = []
    /// Where what's dragged over the card would land, as a slot in the row without this shelf's
    /// dragged items. Nil while nothing is over the card.
    private(set) var dropSlot: Int?
    /// How far the dragged icon is from the slot it would land in, along the row: dropped items
    /// glide from it into their slot.
    private(set) var iconOffset: CGFloat = 0

    /// A flipped view behind the Shelf tab, in `space`: the share picker points at frames in it,
    /// and Quick Look zooms out of them.
    @ObservationIgnored weak var anchorView: NSView?
    /// Where the items sit in the row, leaving out how far a dragged one is lifted off its slot.
    @ObservationIgnored var itemFrames: [UUID: CGRect] = [:]
    @ObservationIgnored var iconFrames: [UUID: CGRect] = [:]
    /// The part of the row that's in view, and the card around it.
    @ObservationIgnored var rowFrame = CGRect.zero
    @ObservationIgnored var cardFrame = CGRect.zero
    /// Where the row's first slot starts, moving as the row scrolls.
    @ObservationIgnored var rowLeading: CGFloat = 0
    @ObservationIgnored var shareButtonFrame = CGRect.zero
    @ObservationIgnored var thumbnails: [UUID: NSImage] = [:]
    @ObservationIgnored private weak var keyPanel: NotchPanel?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var spacePressedAt: Date?
    @ObservationIgnored private var typed = (text: "", at: Date.distantPast)
    /// The item last pressed, and how far into it: a drag holds its icon at that spot.
    @ObservationIgnored private var pressed: (id: UUID, offset: CGFloat)?
    /// Something was just dropped on the card. SwiftUI still sends an update for it a moment
    /// later, which would open the gap again.
    @ObservationIgnored private var hasDropped = false

    init(model: NotchViewModel) {
        self.model = model
    }

    private var store: ShelfStore { model.services.shelf }

    var order: [UUID] { store.items.map(\.id) }

    /// What the AirDrop and Share buttons act on: the selection, or the whole shelf.
    var selectedOrAll: [UUID] { selection.isEmpty ? order : selection.ordered(order) }

    /// What a context-menu command on `id` acts on.
    func targets(for id: UUID) -> [UUID] { selection.targets(for: id, in: order) }

    /// The items the row shows, in its order. While this shelf's own items are dragged over the
    /// card they already sit, hidden, where they'd land, so the others make way for them.
    var rowItems: [ShelfItem] {
        let items = shownItems
        guard let dropSlot, !draggedIDs.isEmpty else { return items }
        var row = items.filter { !draggedIDs.contains($0.id) }
        row.insert(contentsOf: items.filter { draggedIDs.contains($0.id) }, at: min(dropSlot, row.count))
        return row
    }

    /// Where the row opens a gap for files dragged in from elsewhere: before the item at this
    /// index into `rowItems`.
    var gapIndex: Int? { draggedIDs.isEmpty ? dropSlot : nil }

    /// Whether `id` is one of this shelf's items dragged over the card, holding its slot.
    func isLifted(_ id: UUID) -> Bool { dropSlot != nil && draggedIDs.contains(id) }

    /// The items whose files are still there, as the row shows them when nothing is dragged.
    private var shownItems: [ShelfItem] { store.items.filter { store.url(for: $0) != nil } }

    // MARK: - Lifecycle

    func start() {
        store.prune()
        selection.keep(only: order)
        selectRecentlyAdded()
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown, .keyUp:
                return self.handleKey(event) ? nil : event
            default:
                self.handleMouseDown(event)
                return event
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if ShelfQuickLook.shared.isShowing(for: self) { ShelfQuickLook.shared.close() }
        keyPanel?.returnKeyboard()
    }

    /// Takes the keyboard, as clicking into a Finder window does.
    func focus() {
        guard let panel = anchorView?.window as? NotchPanel else { return }
        keyPanel = panel
        panel.takeKeyboard()
    }

    // MARK: - Pointer

    /// Any click on the Shelf hands it the keyboard. Like Finder, pressing an item that isn't
    /// selected selects it right away, so dragging it carries that item; a right-click does too,
    /// for its menu.
    private func handleMouseDown(_ event: NSEvent) {
        guard let view = anchorView, let window = event.window, window === view.window else { return }
        let location = view.convert(event.locationInWindow, from: nil)
        guard view.bounds.contains(location) else { return }
        focus()
        guard !isConfirmingClear, let id = item(at: location) else { return }
        pressed = (id, location.x - (itemFrames[id]?.minX ?? location.x))
        guard !selection.contains(id) else { return }
        // A Control-click is a right-click too.
        if event.type == .rightMouseDown || event.modifierFlags.isDisjoint(with: [.command, .shift]) {
            selection.select(id)
        }
    }

    /// The item under `location` (in `space`), if it's in the visible part of the row.
    private func item(at location: CGPoint) -> UUID? {
        guard rowFrame.contains(location) else { return nil }
        return order.first { itemFrames[$0]?.contains(location) == true }
    }

    /// A click on an item (once its mouse-down selected it): ⌘ adds or removes it, ⇧ adds the
    /// items from the last one clicked, and a double-click opens it.
    func click(_ id: UUID, event: NSEvent?) {
        focus()
        let flags = event?.modifierFlags.intersection([.command, .shift]) ?? []
        if flags.isEmpty, (event?.clickCount ?? 1) >= 2 {
            open(targets(for: id))
            return
        }
        selection.click(id, in: order, extending: flags.contains(.shift), toggling: flags.contains(.command))
        followSelectionInQuickLook()
    }

    func clickBackground() {
        focus()
        selection.clear()
    }

    // MARK: - Keys

    /// Keys that reach the notch (once the Shelf has the keyboard) or this shelf's Quick Look.
    /// Returns whether the key was used up.
    private func handleKey(_ event: NSEvent) -> Bool {
        let quickLook = ShelfQuickLook.shared
        let inQuickLook = event.window is QLPreviewPanel && quickLook.isShowing(for: self)
        guard inQuickLook || (event.window != nil && event.window === anchorView?.window) else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if event.type == .keyUp {
            if event.keyCode == KeyCode.space {
                releaseSpace()
                return true
            }
            return !inQuickLook
        }
        if isConfirmingClear {
            switch event.keyCode {
            case KeyCode.escape: cancelClear()
            case KeyCode.return, KeyCode.enter: confirmClear()
            default: break
            }
            return true
        }

        switch event.keyCode {
        case KeyCode.space where flags.isEmpty:
            pressSpace(isRepeat: event.isARepeat)
            return true
        case KeyCode.escape where flags.isEmpty:
            escape()
            return true
        case KeyCode.left where flags.isSubset(of: [.shift]), KeyCode.right where flags.isSubset(of: [.shift]):
            // Quick Look steps through several items by itself.
            if inQuickLook, quickLook.urls.count > 1 { return false }
            selection.move(by: event.keyCode == KeyCode.left ? -1 : 1, in: order, extending: flags == [.shift])
            followSelectionInQuickLook()
            return true
        case KeyCode.home where flags.isEmpty, KeyCode.end where flags.isEmpty:
            selection.moveToEnd(event.keyCode == KeyCode.end, in: order)
            followSelectionInQuickLook()
            return true
        case KeyCode.down where flags == [.command]:
            open(selection.ordered(order))
            return true
        case KeyCode.delete where flags.isEmpty || flags == [.command], KeyCode.forwardDelete where flags.isEmpty:
            remove(selection.ordered(order))
            return true
        default:
            break
        }

        if flags.contains(.command) {
            switch (event.charactersIgnoringModifiers?.lowercased(), flags) {
            case ("c", [.command]): copy(selection.ordered(order))
            case ("a", [.command]): selection.selectAll(order)
            case ("a", [.command, .option]): selection.clear()
            case ("o", [.command]): open(selection.ordered(order))
            case ("y", [.command]): toggleQuickLook()
            case ("w", [.command]) where inQuickLook: quickLook.close()
            // Anything else would reach DyNotch's own menu: ⌘Q would quit it, ⌘H hide the notch.
            default: break
            }
            return true
        }
        // Quick Look's own keys, such as the arrows when it shows several items.
        if inQuickLook { return false }
        if flags.isSubset(of: [.shift]), let characters = event.characters, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) {
            typeSelect(characters)
        }
        // Nothing else in the notch takes keys: use them up rather than beep.
        return true
    }

    private func pressSpace(isRepeat: Bool) {
        guard !isRepeat else { return }
        if ShelfQuickLook.shared.isShowing(for: self) {
            ShelfQuickLook.shared.close()
            spacePressedAt = nil
        } else {
            quickLook()
            spacePressedAt = .now
        }
    }

    /// Space held down opened a peek: letting go of it closes the preview again.
    private func releaseSpace() {
        if let pressed = spacePressedAt, Date.now.timeIntervalSince(pressed) >= Self.peekDelay {
            ShelfQuickLook.shared.close()
        }
        spacePressedAt = nil
    }

    private func escape() {
        if ShelfQuickLook.shared.isShowing(for: self) {
            ShelfQuickLook.shared.close()
        } else if !selection.isEmpty {
            selection.clear()
        } else {
            model.close()
        }
    }

    /// Selects the first item whose name starts with what's been typed in the last second.
    private func typeSelect(_ characters: String) {
        let now = Date.now
        typed = (now.timeIntervalSince(typed.at) < 1 ? typed.text + characters : characters, now)
        let match = store.items.first {
            $0.name.range(of: typed.text, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
        guard let match else { return }
        selection.select(match.id)
        followSelectionInQuickLook()
    }

    // MARK: - Quick Look

    /// Previews `ids` (the selection, or the whole shelf when nothing is selected), starting at
    /// the item last moved to.
    func quickLook(_ ids: [UUID]? = nil) {
        let files = files(for: ids ?? selectedOrAll)
        guard !files.isEmpty else { return }
        if !ShelfQuickLook.shared.isVisible { focus() }
        let start = selection.cursor.flatMap { cursor in files.firstIndex { $0.id == cursor } } ?? 0
        ShelfQuickLook.shared.show(files.map(\.url), at: start, for: self)
    }

    func toggleQuickLook() {
        if ShelfQuickLook.shared.isShowing(for: self) {
            ShelfQuickLook.shared.close()
        } else {
            quickLook()
        }
    }

    /// An open preview follows the selection, as Finder's does.
    private func followSelectionInQuickLook() {
        guard ShelfQuickLook.shared.isShowing(for: self), !selection.isEmpty else { return }
        quickLook()
    }

    /// Where `url`'s icon is on screen, for Quick Look to zoom out of; nil when it's scrolled away.
    func screenFrame(of url: URL) -> NSRect? {
        guard let view = anchorView, let window = view.window, let id = id(of: url),
              let frame = iconFrames[id], rowFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
        else { return nil }
        return window.convertToScreen(view.convert(frame, to: nil))
    }

    func image(of url: URL) -> NSImage {
        id(of: url).flatMap { thumbnails[$0] } ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    private func id(of url: URL) -> UUID? {
        store.items.first { store.url(for: $0) == url }?.id
    }

    // MARK: - Commands

    func open(_ ids: [UUID]) {
        store.urls(for: ids).forEach { NSWorkspace.shared.open($0) }
    }

    func showInFinder(_ ids: [UUID]) {
        let urls = store.urls(for: ids)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func airDrop(_ ids: [UUID]) {
        AirDropService.send(store.urls(for: ids))
    }

    /// Puts the files on the clipboard, as Finder's Copy does: paste them into a folder or a mail.
    func copy(_ ids: [UUID]) {
        let urls = store.urls(for: ids)
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
    }

    /// Shows the share picker under the item `id`.
    func share(_ ids: [UUID], from id: UUID) {
        share(ids, under: itemFrames[id])
    }

    /// The Share button shares the selection, or everything.
    func shareFromButton() {
        focus()
        share(selectedOrAll, under: shareButtonFrame)
    }

    private func share(_ ids: [UUID], under frame: CGRect?) {
        share(store.urls(for: ids), under: frame)
    }

    private func share(_ urls: [URL], under frame: CGRect?) {
        guard let view = anchorView else { return }
        // The anchor view is flipped, so its bottom edge is maxY.
        ShelfSharing.shared.show(urls, relativeTo: frame ?? view.bounds, of: view, preferredEdge: .maxY)
    }

    func remove(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if ShelfQuickLook.shared.isShowing(for: self) { ShelfQuickLook.shared.close() }
        withAnimation(.notchQuick) { store.remove(Set(ids)) }
        selection.keep(only: order)
    }

    func askToClear() {
        focus()
        withAnimation(.notchQuick) { isConfirmingClear = true }
    }

    func cancelClear() {
        withAnimation(.notchQuick) { isConfirmingClear = false }
    }

    func confirmClear() {
        if ShelfQuickLook.shared.isShowing(for: self) { ShelfQuickLook.shared.close() }
        selection.clear()
        withAnimation(.notchQuick) {
            store.removeAll()
            isConfirmingClear = false
        }
    }

    // MARK: - Dragging

    /// What's dragged out: the files of `ids` (the selection when the pressed item is part of it).
    func files(for ids: [UUID]) -> [ShelfFile] {
        ids.compactMap { id in
            store.items.first { $0.id == id }.flatMap(store.url(for:)).map { ShelfFile(id: id, url: $0) }
        }
    }

    func dragSessionUpdated(_ session: DragSession) {
        switch session.phase {
        case .initial, .active:
            let ids = Set(session.draggedItemIDs(for: UUID.self))
            if ids != draggedIDs { withAnimation(.notchQuick) { draggedIDs = ids } }
        case .ended:
            // Dropped on the card, the items show up in their new places, where their drag images
            // slid (or, without that, where their icon was, gliding in); anywhere else, they're
            // back in their old ones.
            guard !draggedIDs.isEmpty else { return }
            withAnimation(.notchQuick) {
                draggedIDs = []
                dropSlot = nil
                iconOffset = 0
            }
        default:
            // The data transfer can complete while the drag is still going on, even as it starts.
            break
        }
    }

    func dragEntered(at x: CGFloat) {
        hasDropped = false
        ShelfDropLanding.install(in: anchorView?.window)
        dragMoved(to: x)
    }

    /// Something is dragged over the card, the pointer at `x` in the card's coordinates: the row
    /// makes way where it would land.
    func dragMoved(to x: CGFloat) {
        guard !hasDropped else { return }
        let slot = slot(at: x)
        let offset = draggedIDs.isEmpty ? 0 : iconOffset(at: x, in: slot)
        if slot != dropSlot {
            withAnimation(.notchQuick) {
                dropSlot = slot
                iconOffset = offset
            }
        } else if offset != iconOffset {
            iconOffset = offset
        }
    }

    func dragExited() {
        guard dropSlot != nil else { return }
        withAnimation(.notchQuick) {
            dropSlot = nil
            iconOffset = 0
        }
    }

    /// Moves this shelf's own items to where they were dropped, or adds what came from elsewhere
    /// there.
    func drop(_ providers: [NSItemProvider], at x: CGFloat) -> Bool {
        let slot = slot(at: x)
        hasDropped = true
        guard !draggedIDs.isEmpty else {
            let index = storeIndex(ofSlot: slot, in: shownItems)
            Task {
                await store.add(providers: providers, at: index)
                // What was added takes the gap's place.
                withAnimation(.notchQuick) { dropSlot = nil }
                selectRecentlyAdded()
            }
            return true
        }
        // The row already shows them in their new places. They stay hidden there until the drag
        // ends, while the system holds their drag images: it slides them into those places (see
        // `ShelfDropLanding`), or else leaves them where they were let go.
        let rest = shownItems.filter { !draggedIDs.contains($0.id) }
        store.move(draggedIDs, to: storeIndex(ofSlot: slot, in: rest))
        if let view = anchorView {
            let landing = files(for: order.filter(draggedIDs.contains)).compactMap { file in
                itemFrames[file.id].map { (url: file.url, frame: view.convert($0, to: nil)) }
            }
            if ShelfDropLanding.send(landing) { iconOffset = 0 }
        }
        return true
    }

    /// Selects what was just dropped on the Shelf (and scrolls to it), as Finder does with what
    /// was copied in.
    private func selectRecentlyAdded() {
        let added = store.takeRecentlyAdded()
        if !added.isEmpty { selection.select(added) }
    }

    /// Files dropped on the AirDrop button: this shelf's own items, or whatever came from elsewhere.
    func airDropDrop(_ providers: [NSItemProvider]) -> Bool {
        if !draggedIDs.isEmpty {
            airDrop(order.filter(draggedIDs.contains))
        } else {
            Task { await AirDropService.send(providers: providers, store: store) }
        }
        return true
    }

    /// Files dropped on the Share button get the share picker under it: this shelf's own items, or
    /// whatever came from elsewhere.
    func shareDrop(_ providers: [NSItemProvider]) -> Bool {
        let dragged = order.filter(draggedIDs.contains)
        Task {
            let urls = dragged.isEmpty ? await ShelfStore.fileURLs(from: providers) : store.urls(for: dragged)
            focus()
            share(urls, under: shareButtonFrame)
        }
        return true
    }

    /// This shelf's own items dropped on the Clear button leave the shelf, as ⌫ removes them.
    func clearDrop() -> Bool {
        guard !draggedIDs.isEmpty else { return false }
        remove(order.filter(draggedIDs.contains))
        return true
    }

    /// The slot, in the row without this shelf's dragged items, that what's dragged would land
    /// in with the pointer at `x` (in the card's coordinates): the one nearest its icon. Worked
    /// out from the pointer alone, not from where the items are drawn, so the row making way
    /// can't move it.
    private func slot(at x: CGFloat) -> Int {
        let icon = draggedIcon(at: x)
        let slot = Int((icon.leading / ShelfMetrics.slot).rounded()) - icon.index
        return min(max(slot, 0), shownItems.count(where: { !draggedIDs.contains($0.id) }))
    }

    /// How far the dragged icon is from its item's place with the dragged items in `slot`.
    private func iconOffset(at x: CGFloat, in slot: Int) -> CGFloat {
        let icon = draggedIcon(at: x)
        return icon.leading - CGFloat(slot + icon.index) * ShelfMetrics.slot
    }

    /// Where the dragged icon's leading edge is along the row with the pointer at `x` (in the
    /// card's coordinates), and which of the dragged items it is. This shelf's items hang from
    /// where they were pressed; files from elsewhere are taken to hang from their middle.
    private func draggedIcon(at x: CGFloat) -> (leading: CGFloat, index: Int) {
        let along = x + cardFrame.minX - rowLeading
        let dragged = shownItems.map(\.id).filter(draggedIDs.contains)
        if let pressed, let index = dragged.firstIndex(of: pressed.id) {
            return (along - pressed.offset, index)
        }
        return (along - ShelfMetrics.itemWidth / 2, 0)
    }

    /// The index into the store's items of the item at `slot` in `items`, or the end.
    private func storeIndex(ofSlot slot: Int, in items: [ShelfItem]) -> Int {
        guard slot < items.count else { return store.items.count }
        return store.items.firstIndex { $0.id == items[slot].id } ?? store.items.count
    }
}

private enum KeyCode {
    static let `return`: UInt16 = 36
    static let delete: UInt16 = 51
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let enter: UInt16 = 76
    static let home: UInt16 = 115
    static let forwardDelete: UInt16 = 117
    static let end: UInt16 = 119
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
}
