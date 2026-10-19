import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, layout
    case nowPlaying, clock, weather, calendar, timers, camera
    case live, hud
    case permissions, about

    /// The sidebar's groups: the notch itself, what it shows, what pops up in it, and the app.
    static let groups: [[SettingsPane]] = [
        [.general, .layout],
        [.nowPlaying, .clock, .weather, .calendar, .timers, .camera],
        [.live, .hud],
        [.permissions, .about],
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .layout: String(localized: "Layout")
        case .nowPlaying: String(localized: "Now Playing")
        case .clock: String(localized: "Clock")
        case .weather: String(localized: "Weather")
        case .calendar: String(localized: "Calendar & Reminders")
        case .timers: String(localized: "Timers")
        case .camera: String(localized: "Camera")
        case .live: String(localized: "Live Activities")
        case .hud: String(localized: "Volume & Brightness")
        case .permissions: String(localized: "Permissions")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .layout: "rectangle.3.group.fill"
        case .nowPlaying: "music.note"
        case .clock: "clock.fill"
        case .weather: "cloud.sun.fill"
        case .calendar: "calendar"
        case .timers: "timer"
        case .camera: "web.camera.fill"
        case .live: "bolt.horizontal.fill"
        case .hud: "speaker.wave.2.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }

    /// The feature panes take their widget's color in the Layout editor.
    var color: Color {
        switch self {
        case .general: .gray
        case .layout: .black
        case .nowPlaying: HomeWidget.media.tint
        case .clock: HomeWidget.clock.tint
        case .weather: HomeWidget.weather.tint
        case .calendar: HomeWidget.calendar.tint
        case .timers: HomeWidget.timer.tint
        case .camera: .green
        case .live: .indigo
        case .hud: .blue
        case .permissions: .green
        case .about: .gray
        }
    }
}

/// The Settings window. Built by hand (not a SwiftUI `Settings` scene) so it can be
/// opened from the notch, which isn't part of the SwiftUI scene graph.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let selection = SettingsSelection()

    func show(pane: SettingsPane? = nil) {
        if let pane { selection.pane = pane }
        if window == nil {
            let root = SettingsView(selection: selection).environment(AppServices.shared)
            let window = SettingsWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = NSHostingController(rootView: root)
            window.title = String(localized: "DyNotch Settings")
            // The title bar isn't made transparent: that takes away the bar behind the pane's
            // title, and the pane then scrolls up through the title instead of under it.
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 760, height: 540))
            window.minSize = NSSize(width: 640, height: 420)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Ends typing in a field. The window is kept for next time, so a number typed without
    /// pressing Return would otherwise still be half-typed when it opens again.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }
}

/// The toolbar SwiftUI puts on the window holds only the sidebar button and the title, so
/// right-clicking it shouldn't offer Icon and Text, Icon Only and Text Only.
private final class SettingsWindow: NSWindow {
    override var toolbar: NSToolbar? {
        didSet { toolbar?.allowsDisplayModeCustomization = false }
    }
}

@Observable
final class SettingsSelection {
    var pane: SettingsPane = .general
}
