import AppKit

/// Watches the pointer system-wide. Mouse-move monitors don't need any permission.
final class MouseMonitor {
    var handler: ((NSEvent.EventType, CGPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler?(event.type, NSEvent.mouseLocation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler?(event.type, NSEvent.mouseLocation)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
