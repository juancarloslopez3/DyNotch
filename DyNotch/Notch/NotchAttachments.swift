import AppKit

/// Windows DyNotch opens beside the open notch: Quick Look and the share picker. Like a menu, one
/// keeps the notch open while it's up, and clicking in it doesn't count as clicking outside.
enum NotchAttachments {
    static var isShowing: Bool { ShelfQuickLook.shared.isVisible || ShelfSharing.shared.isShowing }

    /// Whether `location` (in screen coordinates) is on one of them.
    static func contains(_ location: CGPoint) -> Bool {
        isShowing && NSApp.windows.contains { $0.isVisible && !($0 is NotchPanel) && $0.frame.contains(location) }
    }
}
