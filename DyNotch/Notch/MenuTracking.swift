import AppKit

/// Tracks whether any menu (context menus, pickers) is open, so the notch doesn't
/// collapse underneath it when the pointer moves into the menu.
enum MenuTracking {
    private(set) static var isTracking = false
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { isTracking = true }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { isTracking = false }
        })
    }
}
