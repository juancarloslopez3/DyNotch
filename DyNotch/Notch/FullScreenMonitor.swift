import AppKit

/// Detects when another app is full screen on a notch's display, and whether it's showing a
/// video there, so the notch can stay out of the way (HUDs still show) and the player can keep
/// clear of a full-screen video.
final class FullScreenMonitor {
    private weak var services: AppServices?
    private var observers: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?

    func start(services: AppServices) {
        self.services = services
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleCheck() }
            })
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Space switches animate; check again once the animation has settled.
    private func scheduleCheck() {
        check()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.check()
        }
    }

    private func check() {
        guard let services else { return }
        let spaces = DisplaySpaces.current()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = ((CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? [])
            .compactMap(FullScreenDetection.Window.init)
            .filter { $0.pid != ownPID }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for controller in services.notch.controllers {
            let model = controller.model
            // CGWindow bounds use a top-left origin on the primary screen.
            let frame = model.geometry.screenFrame
            let screen = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            let space = controller.screenID.uuidString.flatMap { spaces[$0] } ?? spaces["Main"]
            let tiles = FullScreenDetection.apps(currentSpace: space, windows: windows, screen: screen)
            let isFullScreen = tiles != nil
            let videoApps = Set((tiles ?? []).filter { !Self.showsToolbar($0) }
                .compactMap { NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier })
            if model.isFullScreenActive != isFullScreen {
                model.isFullScreenActive = isFullScreen
            }
            if model.fullScreenVideoApps != videoApps {
                model.fullScreenVideoApps = videoApps
            }
        }
    }

    /// Whether the window an app fills the screen with still has its toolbar: the app itself
    /// in full screen (Safari browsing), not a video it put there. Safari plays a full-screen
    /// video in a window of its own, without one. Unknown windows, or no Accessibility, count
    /// as videos.
    private static func showsToolbar(_ tile: FullScreenDetection.Tile) -> Bool {
        guard let id = tile.window, AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(tile.pid)
        // Checked every couple of seconds on the main thread; a busy app mustn't hold it up.
        AXUIElementSetMessagingTimeout(app, 0.25)
        let windows: [AXUIElement] = app.attribute(kAXWindowsAttribute) ?? []
        guard let window = windows.first(where: { AccessibilityWindows.windowID(of: $0) == id }) else { return false }
        // Safari moves its toolbar into a group of its own in full screen. Deeper down is the
        // page, whose controls can call themselves toolbars too.
        var level = [window]
        for _ in 0..<2 {
            level = level.flatMap { $0.attribute(kAXChildrenAttribute) ?? [] }
            if level.contains(where: { $0.attribute(kAXRoleAttribute) == kAXToolbarRole }) { return true }
        }
        return false
    }
}

/// Tells from a display's Space and the windows on screen which apps are full screen there.
///
/// The menu bar's window stays on screen in a full-screen Space (macOS 27), so it can't tell
/// one apart from a desktop with a window zoomed below the menu bar and the Dock hidden.
nonisolated enum FullScreenDetection {
    /// A window in the window list.
    struct Window: Equatable {
        var pid: pid_t
        var number: CGWindowID
        var layer: Int
        /// Top-left origin on the primary screen, as the window list has it.
        var bounds: CGRect

        init(pid: pid_t, number: CGWindowID = kCGNullWindowID, layer: Int, bounds: CGRect) {
            self.pid = pid
            self.number = number
            self.layer = layer
            self.bounds = bounds
        }

        init?(_ info: [String: Any]) {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) })
            else { return nil }
            self.init(pid: pid_t(pid), number: CGWindowID(number), layer: layer, bounds: bounds)
        }
    }

    /// An app full screen, and the window it fills the screen with when that's known. Safari
    /// browsing in full screen fills it with its own window; a video it puts in full screen
    /// gets a window (and a Space) of its own.
    struct Tile: Equatable {
        var pid: pid_t
        var window: CGWindowID?
    }

    /// The apps full screen on `screen`: one, or two side by side (empty when the Space
    /// doesn't say); `nil` when nothing is full screen there. `windows` go front to back.
    static func apps(currentSpace: [String: Any]?, windows: [Window], screen: CGRect) -> [Tile]? {
        // A full-screen Space (type 4) lists the apps tiled in it.
        if let space = currentSpace, space["type"] as? Int == 4 {
            let tiles = ((space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] ?? [])
                .compactMap { tile in
                    (tile["pid"] as? Int).map { Tile(pid: pid_t($0), window: (tile["TileWindowID"] as? Int).map(CGWindowID.init)) }
                }
            if !tiles.isEmpty { return tiles }
            return [space["pid"] as? Int].compactMap { $0 }
                .map { Tile(pid: pid_t($0), window: (space["fs_wid"] as? Int).map(CGWindowID.init)) }
        }
        // Some games and players fill the screen without a Space of their own. Their window
        // then covers the menu bar as well, which an ordinary window can't.
        if let front = windows.first(where: { $0.layer == 0 && $0.bounds.intersects(screen) }),
           front.bounds.insetBy(dx: -1, dy: -1).contains(screen) {
            return [Tile(pid: front.pid, window: front.number)]
        }
        return nil
    }
}

private extension CGDirectDisplayID {
    /// The display's UUID, which SkyLight names displays by.
    var uuidString: String? {
        CGDisplayCreateUUIDFromDisplayID(self).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }
}
