import Foundation
import Observation

enum OpenMode: String, CaseIterable, Identifiable {
    case hover, click
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hover: String(localized: "Hover")
        case .click: String(localized: "Click")
        }
    }
}

enum TemperatureUnitPreference: String, CaseIterable, Identifiable {
    case automatic, celsius, fahrenheit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .celsius: String(localized: "Celsius")
        case .fahrenheit: String(localized: "Fahrenheit")
        }
    }
}

/// Modifier that turns the display brightness keys into keyboard backlight keys.
enum BacklightModifier: String, CaseIterable, Identifiable {
    case control, option, command, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .control: String(localized: "⌃ Control")
        case .option: String(localized: "⌥ Option")
        case .command: String(localized: "⌘ Command")
        case .none: String(localized: "Off")
        }
    }
}

/// The displays the brightness keys adjust.
enum BrightnessKeyScope: String, CaseIterable, Identifiable {
    case pointer, all, builtIn
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pointer: String(localized: "Display With the Pointer")
        case .all: String(localized: "All Displays")
        case .builtIn: String(localized: "Built-in Display Only")
        }
    }
}

/// Swiping sideways over the open notch moves to the tab beside the current one.
enum TabSwipe: String, CaseIterable, Identifiable {
    case off, twoFingers, threeFingers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .twoFingers: String(localized: "With Two Fingers")
        case .threeFingers: String(localized: "With Three Fingers")
        }
    }
}

/// How much of the open notch the Camera tab's picture takes.
enum CameraSize: String, CaseIterable, Identifiable {
    case standard, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .large: String(localized: "Large")
        }
    }
}

/// The app the Now Playing card offers to open while nothing is playing.
enum MusicPlayer: String, CaseIterable, Identifiable {
    case music, spotify, deezer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .music: String(localized: "Music", comment: "The Music app")
        case .spotify: "Spotify"
        case .deezer: "Deezer"
        }
    }
    var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .deezer: "com.deezer.deezer-desktop"
        }
    }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, timers, camera
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .shelf: String(localized: "Shelf")
        case .timers: String(localized: "Timers")
        case .camera: String(localized: "Camera")
        }
    }
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.full.fill"
        case .timers: "timer"
        case .camera: "web.camera.fill"
        }
    }
}

/// Helpers for the orders of tabs, Home columns and timers. A stored order lists every case
/// once, hidden ones included, so they come back where they were.
nonisolated enum LayoutOrder {
    /// The stored values that are still known, without repeats, followed by any cases they
    /// lack (e.g. ones added in a later version) in their declared order.
    static func complete<Item: CaseIterable & RawRepresentable & Equatable>(_ stored: [String]?) -> [Item]
    where Item.RawValue == String {
        var order: [Item] = []
        for item in (stored ?? []).compactMap({ Item(rawValue: $0) }) + Item.allCases where !order.contains(item) {
            order.append(item)
        }
        return order
    }

    /// `order` with the items in `shown` put in that order, each taking the place one of them
    /// had, so the hidden ones stay where they are.
    static func rearranged<Item: Equatable>(_ order: [Item], shown: [Item]) -> [Item] {
        var next = shown.makeIterator()
        return order.map { shown.contains($0) ? next.next() ?? $0 : $0 }
    }

    /// `order` with `item` swapped with the one `step` places along, when there is one.
    static func moved<Item: Equatable>(_ item: Item, by step: Int, in order: [Item]) -> [Item] {
        guard let index = order.firstIndex(of: item), order.indices.contains(index + step) else { return order }
        var order = order
        order.swapAt(index, index + step)
        return order
    }
}

nonisolated struct SavedCity: Codable, Equatable, Hashable, Sendable {
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double
    /// ISO 3166-1 alpha-2, e.g. "DK". Missing on cities saved before it was kept.
    var countryCode: String? = nil

    /// The country's flag, e.g. 🇩🇰.
    var flag: String? {
        guard let code = countryCode?.uppercased(), code.count == 2,
              code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) })
        else { return nil }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }))
    }
}

/// All user preferences, persisted in `UserDefaults`.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: General
    var openMode: OpenMode { didSet { defaults.set(openMode.rawValue, forKey: "openMode") } }
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    /// Swiping down with two fingers over the closed notch opens it, and up over the open one
    /// closes it.
    var swipeToOpen: Bool { didSet { defaults.set(swipeToOpen, forKey: "swipeToOpen") } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    var showOnExternalDisplays: Bool { didSet { defaults.set(showOnExternalDisplays, forKey: "showOnExternalDisplays") } }
    var hideInFullScreen: Bool { didSet { defaults.set(hideInFullScreen, forKey: "hideInFullScreen") } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }

    // MARK: Appearance
    var tintWithArtwork: Bool { didSet { defaults.set(tintWithArtwork, forKey: "tintWithArtwork") } }
    var barsFollowMusic: Bool { didSet { defaults.set(barsFollowMusic, forKey: "barsFollowMusic") } }
    var showCompactMedia: Bool { didSet { defaults.set(showCompactMedia, forKey: "showCompactMedia") } }
    /// Nothing about the music shows beside the notch while the app playing is full screen,
    /// as a video usually is.
    var hidePlayerInFullScreen: Bool { didSet { defaults.set(hidePlayerInFullScreen, forKey: "hidePlayerInFullScreen") } }
    var showIdleClock: Bool { didSet { defaults.set(showIdleClock, forKey: "showIdleClock") } }
    var musicPlayer: MusicPlayer { didSet { defaults.set(musicPlayer.rawValue, forKey: "musicPlayer") } }

    // MARK: Layout
    /// Every tab, in tab-bar order.
    var tabOrder: [NotchTab] { didSet { defaults.set(tabOrder.map(\.rawValue), forKey: "tabOrder") } }
    var hiddenTabs: [NotchTab] { didSet { defaults.set(hiddenTabs.map(\.rawValue), forKey: "hiddenTabs") } }
    /// The tab the notch opens on; `nil` reopens the last one used.
    var openingTab: NotchTab? { didSet { defaults.set(openingTab?.rawValue, forKey: "openingTab") } }
    /// What the Home tab shows, and where.
    var homeLayout: HomeLayout { didSet { storeCodable(homeLayout, "homeLayout") } }
    var headerBattery: Bool { didSet { defaults.set(headerBattery, forKey: "headerBattery") } }
    /// The gear beside the cut-out; without it, clicking the clock opens Settings.
    var headerSettingsButton: Bool { didSet { defaults.set(headerSettingsButton, forKey: "headerSettingsButton") } }
    var tabSwipe: TabSwipe { didSet { defaults.set(tabSwipe.rawValue, forKey: "tabSwipe") } }
    /// Leaves the tab bar out, while swiping moves between tabs; see `showsTabBar`.
    var hideTabBar: Bool { didSet { defaults.set(hideTabBar, forKey: "hideTabBar") } }

    // MARK: HUD
    var hudVolume: Bool { didSet { defaults.set(hudVolume, forKey: "hudVolume") } }
    var hudBrightness: Bool { didSet { defaults.set(hudBrightness, forKey: "hudBrightness") } }
    var hudKeyboard: Bool { didSet { defaults.set(hudKeyboard, forKey: "hudKeyboard") } }
    var backlightModifier: BacklightModifier { didSet { defaults.set(backlightModifier.rawValue, forKey: "backlightModifier") } }
    var brightnessKeyScope: BrightnessKeyScope { didSet { defaults.set(brightnessKeyScope.rawValue, forKey: "brightnessKeyScope") } }
    /// The brightness last set on each monitor adjusted over DDC/CI, by vendor, model and serial
    /// number, for the monitors that can't say theirs.
    var externalBrightness: [String: Double] { didSet { defaults.set(externalBrightness, forKey: "externalBrightness") } }

    // MARK: Widgets
    var worldClockIDs: [String] { didSet { defaults.set(worldClockIDs, forKey: "worldClockIDs") } }
    var hiddenCalendarIDs: [String] { didSet { defaults.set(hiddenCalendarIDs, forKey: "hiddenCalendarIDs") } }
    var hiddenReminderListIDs: [String] { didSet { defaults.set(hiddenReminderListIDs, forKey: "hiddenReminderListIDs") } }

    // MARK: Weather
    var weatherUseLocation: Bool { didSet { defaults.set(weatherUseLocation, forKey: "weatherUseLocation") } }
    var weatherCity: SavedCity? { didSet { storeCodable(weatherCity, "weatherCity") } }
    var temperatureUnit: TemperatureUnitPreference { didSet { defaults.set(temperatureUnit.rawValue, forKey: "temperatureUnit") } }

    // MARK: Camera
    /// Large grows the open notch on the Camera tab to a picture as wide as the notch.
    var cameraSize: CameraSize { didSet { defaults.set(cameraSize.rawValue, forKey: "cameraSize") } }
    /// The Camera tab shows the picture the way a mirror does; off, the way others see you.
    var cameraMirrored: Bool { didSet { defaults.set(cameraMirrored, forKey: "cameraMirrored") } }

    // MARK: Live activities
    var liveBattery: Bool { didSet { defaults.set(liveBattery, forKey: "liveBattery") } }
    var liveBluetooth: Bool { didSet { defaults.set(liveBluetooth, forKey: "liveBluetooth") } }
    /// Off, connecting AirPods show up beside the notch like any other device.
    var liveAirPodsAnimation: Bool { didSet { defaults.set(liveAirPodsAnimation, forKey: "liveAirPodsAnimation") } }
    var liveMeetings: Bool { didSet { defaults.set(liveMeetings, forKey: "liveMeetings") } }
    var liveFocus: Bool { didSet { defaults.set(liveFocus, forKey: "liveFocus") } }
    var liveCapsLock: Bool { didSet { defaults.set(liveCapsLock, forKey: "liveCapsLock") } }
    var capsLockPersistent: Bool { didSet { defaults.set(capsLockPersistent, forKey: "capsLockPersistent") } }
    var liveSongChange: Bool { didSet { defaults.set(liveSongChange, forKey: "liveSongChange") } }

    // MARK: Timers
    /// Timer, Stopwatch and Pomodoro, top to bottom in the Timers tab.
    var timerOrder: [TimerMode] { didSet { defaults.set(timerOrder.map(\.rawValue), forKey: "timerOrder") } }
    var pomodoroWorkMinutes: Int { didSet { defaults.set(pomodoroWorkMinutes, forKey: "pomodoroWorkMinutes") } }
    var pomodoroShortBreakMinutes: Int { didSet { defaults.set(pomodoroShortBreakMinutes, forKey: "pomodoroShortBreakMinutes") } }
    var pomodoroLongBreakMinutes: Int { didSet { defaults.set(pomodoroLongBreakMinutes, forKey: "pomodoroLongBreakMinutes") } }
    var pomodoroRounds: Int { didSet { defaults.set(pomodoroRounds, forKey: "pomodoroRounds") } }
    var timerSound: Bool { didSet { defaults.set(timerSound, forKey: "timerSound") } }
    /// The sound repeats until it's stopped, the way an iPhone's timer rings.
    var timerAlarm: Bool { didSet { defaults.set(timerAlarm, forKey: "timerAlarm") } }
    /// The tone it rings with, an `AlarmTone` id.
    var timerAlarmTone: String { didSet { defaults.set(timerAlarmTone, forKey: "timerAlarmTone") } }
    var timerNotification: Bool { didSet { defaults.set(timerNotification, forKey: "timerNotification") } }
    var lastTimerDuration: Double { didSet { defaults.set(lastTimerDuration, forKey: "lastTimerDuration") } }

    // MARK: State
    var lastTab: NotchTab { didSet { defaults.set(lastTab.rawValue, forKey: "lastTab") } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    /// The welcome tour's step while it's open, to pick up there if DyNotch quits meanwhile.
    var tourStepToResume: OnboardingStep? { didSet { defaults.set(tourStepToResume?.rawValue, forKey: "tourStepToResume") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) as? Double ?? fallback }

        openMode = OpenMode(rawValue: defaults.string(forKey: "openMode") ?? "") ?? .hover
        hoverDelay = double("hoverDelay", 0.15)
        swipeToOpen = bool("swipeToOpen", true)
        hapticsEnabled = bool("hapticsEnabled", true)
        showOnExternalDisplays = bool("showOnExternalDisplays", false)
        hideInFullScreen = bool("hideInFullScreen", false)
        showMenuBarIcon = bool("showMenuBarIcon", true)

        tintWithArtwork = bool("tintWithArtwork", true)
        barsFollowMusic = bool("barsFollowMusic", true)
        showCompactMedia = bool("showCompactMedia", true)
        hidePlayerInFullScreen = bool("hidePlayerInFullScreen", true)
        showIdleClock = bool("showIdleClock", false)
        musicPlayer = MusicPlayer(rawValue: defaults.string(forKey: "musicPlayer") ?? "") ?? .music

        tabOrder = LayoutOrder.complete(defaults.stringArray(forKey: "tabOrder"))
        hiddenTabs = (defaults.stringArray(forKey: "hiddenTabs") ?? []).compactMap(NotchTab.init(rawValue:))
        openingTab = defaults.string(forKey: "openingTab").flatMap(NotchTab.init(rawValue:))
        // The clock's old switch, "widgetClock", is left behind: it always shows now.
        homeLayout = Self.loadCodable(HomeLayout.self, "homeLayout", defaults) ?? HomeLayout.migrated(
            columnOrder: defaults.stringArray(forKey: "homeColumnOrder"),
            media: bool("widgetMedia", true),
            weather: bool("widgetWeather", true),
            calendar: bool("widgetCalendar", true),
            reminders: bool("widgetReminders", true)
        )
        headerBattery = bool("headerBattery", true)
        headerSettingsButton = bool("headerSettingsButton", true)
        tabSwipe = TabSwipe(rawValue: defaults.string(forKey: "tabSwipe") ?? "") ?? .threeFingers
        hideTabBar = bool("hideTabBar", false)

        hudVolume = bool("hudVolume", true)
        hudBrightness = bool("hudBrightness", true)
        hudKeyboard = bool("hudKeyboard", true)
        backlightModifier = BacklightModifier(rawValue: defaults.string(forKey: "backlightModifier") ?? "") ?? .control
        brightnessKeyScope = BrightnessKeyScope(rawValue: defaults.string(forKey: "brightnessKeyScope") ?? "") ?? .pointer
        externalBrightness = defaults.dictionary(forKey: "externalBrightness") as? [String: Double] ?? [:]

        worldClockIDs = defaults.stringArray(forKey: "worldClockIDs") ?? []
        hiddenCalendarIDs = defaults.stringArray(forKey: "hiddenCalendarIDs") ?? []
        hiddenReminderListIDs = defaults.stringArray(forKey: "hiddenReminderListIDs") ?? []

        weatherUseLocation = bool("weatherUseLocation", true)
        weatherCity = Self.loadCodable(SavedCity.self, "weatherCity", defaults)
        temperatureUnit = TemperatureUnitPreference(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .automatic

        cameraSize = CameraSize(rawValue: defaults.string(forKey: "cameraSize") ?? "") ?? .standard
        cameraMirrored = bool("cameraMirrored", true)

        liveBattery = bool("liveBattery", true)
        liveBluetooth = bool("liveBluetooth", true)
        liveAirPodsAnimation = bool("liveAirPodsAnimation", true)
        liveMeetings = bool("liveMeetings", true)
        liveFocus = bool("liveFocus", true)
        liveCapsLock = bool("liveCapsLock", true)
        capsLockPersistent = bool("capsLockPersistent", false)
        liveSongChange = bool("liveSongChange", true)

        timerOrder = LayoutOrder.complete(defaults.stringArray(forKey: "timerOrder"))
        pomodoroWorkMinutes = int("pomodoroWorkMinutes", 25)
        pomodoroShortBreakMinutes = int("pomodoroShortBreakMinutes", 5)
        pomodoroLongBreakMinutes = int("pomodoroLongBreakMinutes", 15)
        pomodoroRounds = int("pomodoroRounds", 4)
        timerSound = bool("timerSound", true)
        timerAlarm = bool("timerAlarm", false)
        timerAlarmTone = defaults.string(forKey: "timerAlarmTone") ?? AlarmTone.standard.id
        timerNotification = bool("timerNotification", true)
        lastTimerDuration = double("lastTimerDuration", 5 * 60)

        lastTab = NotchTab(rawValue: defaults.string(forKey: "lastTab") ?? "") ?? .home
        hasCompletedOnboarding = bool("hasCompletedOnboarding", false)
        tourStepToResume = (defaults.object(forKey: "tourStepToResume") as? Int).flatMap(OnboardingStep.init(rawValue:))
    }

    // MARK: Layout

    /// The tabs in the tab bar, in order. Never empty.
    var visibleTabs: [NotchTab] {
        let visible = tabOrder.filter { !hiddenTabs.contains($0) }
        return visible.isEmpty ? Array(tabOrder.prefix(1)) : visible
    }

    /// Shows or hides a tab. The last one showing stays.
    func setTab(_ tab: NotchTab, visible: Bool) {
        if visible {
            hiddenTabs.removeAll { $0 == tab }
        } else if !hiddenTabs.contains(tab), visibleTabs.count > 1 {
            hiddenTabs.append(tab)
        }
    }

    /// Whether the open notch shows its tab bar. It can only be hidden while swiping moves
    /// between tabs.
    var showsTabBar: Bool { tabSwipe == .off || !hideTabBar }

    /// `openingTab` while it's in the tab bar; a hidden one means reopening the last tab.
    var effectiveOpeningTab: NotchTab? {
        openingTab.flatMap { visibleTabs.contains($0) ? $0 : nil }
    }

    /// The tab in the tab bar with the most about `widget`: `ownTab`, the one all about it, else
    /// Home while it has the widget.
    func tab(about widget: HomeWidget, ownTab: NotchTab? = nil) -> NotchTab? {
        [ownTab, homeLayout.contains(widget) ? .home : nil].compactMap { $0 }.first(where: visibleTabs.contains)
    }

    private func storeCodable<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func loadCodable<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
