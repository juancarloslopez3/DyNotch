import AppKit
import Observation

/// Detects file drags anywhere on screen (via the drag pasteboard) and turns the nearest
/// notch into a drop target when the pointer approaches it.
@Observable
final class DragMonitor {
    private(set) var isDraggingFiles = false

    @ObservationIgnored weak var services: AppServices?
    @ObservationIgnored private var changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    /// The open notch the drag started in: its Shelf takes its own items back itself.
    @ObservationIgnored private weak var source: NotchViewModel?
    @ObservationIgnored private var endCheck: Task<Void, Never>?

    /// How close (in points) the pointer must get to the closed notch to reveal the drop zones.
    private static let revealDistance: CGFloat = 40
    /// How far off the shown drop zones the pointer may stray before they hide again.
    private static let keepDistance: CGFloat = 20

    func handleMouse(_ type: NSEvent.EventType, at location: CGPoint) {
        switch type {
        case .leftMouseDown:
            changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            source = services?.notch.models.first { $0.isOpen && $0.isInteractive(at: location) }
        case .leftMouseDragged:
            if !isDraggingFiles, NSPasteboard(name: .drag).changeCount != changeCountAtMouseDown, Self.dragHasDroppableContent() {
                isDraggingFiles = true
                watchForEnd()
            }
            if isDraggingFiles { updateTargets(at: location) }
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
    }

    private func updateTargets(at location: CGPoint) {
        guard let services else { return }
        for model in services.notch.models {
            // Revealed close to the notch. Once shown, kept while the pointer is over the
            // (larger) drop zones, so moving down onto them doesn't hide them.
            let zone = model.isShowingDropTarget
                ? model.shapeRect(for: .dropTarget).insetBy(dx: -Self.keepDistance, dy: -Self.keepDistance)
                : model.shapeRect(for: .closed).insetBy(dx: -Self.revealDistance, dy: -Self.revealDistance)
            // Items dragged out of an open notch's Shelf go back into its row (or onto its AirDrop
            // button), so that notch stays as it is.
            let near = model !== source && zone.extendedToTop(by: 2).contains(location)
            if model.isShowingDropTarget != near {
                model.isShowingDropTarget = near
            }
        }
    }

    /// The mouse-up of a drag that ends over our own panel doesn't always reach the
    /// monitors, so also end when no button is pressed any more.
    private func watchForEnd() {
        endCheck?.cancel()
        endCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self?.endDrag()
                    return
                }
            }
        }
    }

    func endDrag() {
        endCheck?.cancel()
        guard isDraggingFiles else { return }
        isDraggingFiles = false
        services?.notch.models.forEach { $0.isShowingDropTarget = false }
    }

    private static func dragHasDroppableContent() -> Bool {
        let types = NSPasteboard(name: .drag).types ?? []
        return types.contains(.fileURL) || types.contains(.png) || types.contains(.tiff)
            || types.contains(.string) || types.contains(.URL)
    }
}
