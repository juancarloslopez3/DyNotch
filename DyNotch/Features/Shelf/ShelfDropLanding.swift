import AppKit
import ObjectiveC

/// Slides the drag images of the Shelf's own items, dropped back on its row, into their new
/// places, as icons dropped into a Finder window slide into theirs.
///
/// After a drop, SwiftUI has AppKit animate the drag images to their destination but leaves that
/// where they were let go: they hang there, still, for ~0.3 s until the drag ends. SwiftUI doesn't
/// hand out the drop's `NSDraggingInfo` to change it, so this wraps `performDragOperation(_:)` of
/// its private drop target view, found at runtime. If a later macOS changes that, nothing is
/// wrapped, `isAvailable` stays false, and the Shelf glides its items in from where they were let
/// go instead.
enum ShelfDropLanding {
    /// Whether drag images can be sent to their places.
    private(set) static var isAvailable = false
    /// Where the drag image of each file (by path) goes in the drop being performed, in window
    /// coordinates.
    private static var frames: [String: CGRect] = [:]

    /// Wraps the class of SwiftUI's drop targets in `window`, the first time one is found.
    static func install(in window: NSWindow?) {
        guard !isAvailable, let target = window?.contentView.flatMap(dropTarget(in:)) else { return }
        let viewClass: AnyClass = type(of: target)
        let selector = #selector(NSDraggingDestination.performDragOperation(_:))
        // Only a method of that class itself, not one it inherits.
        guard let method = class_getInstanceMethod(viewClass, selector),
              method != class_getSuperclass(viewClass).flatMap({ class_getInstanceMethod($0, selector) })
        else { return }
        typealias Perform = @convention(c) (NSView, Selector, NSDraggingInfo) -> Bool
        let perform = unsafeBitCast(method_getImplementation(method), to: Perform.self)
        let wrapped: @convention(block) (NSView, NSDraggingInfo) -> Bool = { view, info in
            // The drop delegate runs in here and hands over its frames.
            let accepted = perform(view, selector, info)
            if accepted { land(info, in: view) }
            frames = [:]
            return accepted
        }
        method_setImplementation(method, imp_implementationWithBlock(wrapped))
        isAvailable = true
    }

    /// Sends the drag images of `files` to their frames (in window coordinates) as the drop being
    /// performed ends. Returns whether they'll go there.
    static func send(_ files: [(url: URL, frame: CGRect)]) -> Bool {
        guard isAvailable else { return false }
        frames = Dictionary(files.map { ($0.url.standardizedFileURL.path, $0.frame) }) { first, _ in first }
        return true
    }

    private static func land(_ info: NSDraggingInfo, in view: NSView) {
        guard !frames.isEmpty else { return }
        info.animatesToDestination = true
        info.enumerateDraggingItems(options: [], for: view, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            guard let string = (item.item as? NSPasteboardItem)?.string(forType: .fileURL),
                  let url = URL(string: string), let frame = frames[url.standardizedFileURL.path]
            else { return }
            item.draggingFrame = view.convert(frame, from: nil)
        }
    }

    private static func dropTarget(in view: NSView) -> NSView? {
        if !view.registeredDraggedTypes.isEmpty { return view }
        return view.subviews.lazy.compactMap(dropTarget(in:)).first
    }
}
